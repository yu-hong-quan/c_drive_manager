import 'dart:convert';
import 'dart:io';

/// 隔离项状态：保留中 / 即将到期 / 已到期待清理。
enum QuarantineStatus { retained, expiring, expired }

/// 单条隔离记录，对应 PRD 中的原路径、隔离路径、大小、指纹与到期时间。
class QuarantineItem {
  const QuarantineItem({
    required this.id,
    required this.originalPath,
    required this.quarantinePath,
    required this.bytes,
    required this.fingerprint,
    required this.source,
    required this.category,
    required this.displayName,
    required this.createdAt,
    required this.expireAt,
  });

  factory QuarantineItem.fromJson(Map<String, dynamic> json) {
    return QuarantineItem(
      id: json['id'] as String? ?? '',
      originalPath: json['originalPath'] as String? ?? '',
      quarantinePath: json['quarantinePath'] as String? ?? '',
      bytes: _readInt(json['bytes']),
      fingerprint: json['fingerprint'] as String? ?? '',
      source: json['source'] as String? ?? 'unknown',
      category: json['category'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expireAt: DateTime.tryParse(json['expireAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String originalPath;
  final String quarantinePath;
  final int bytes;
  final String fingerprint;
  final String source;
  final String category;
  final String displayName;
  final DateTime createdAt;
  final DateTime expireAt;

  QuarantineStatus statusAt(DateTime now) {
    if (!expireAt.isAfter(now)) return QuarantineStatus.expired;
    // 剩余不足 2 天视为即将到期，便于用户优先处理。
    if (expireAt.difference(now).inHours <= 48) {
      return QuarantineStatus.expiring;
    }
    return QuarantineStatus.retained;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalPath': originalPath,
      'quarantinePath': quarantinePath,
      'bytes': bytes,
      'fingerprint': fingerprint,
      'source': source,
      'category': category,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      'expireAt': expireAt.toIso8601String(),
    };
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// 移入隔离的批量执行结果。
class QuarantineMoveResult {
  const QuarantineMoveResult({
    required this.movedBytes,
    required this.movedFiles,
    required this.skippedFiles,
    required this.failedFiles,
    required this.items,
    this.errorCode,
  });

  final int movedBytes;
  final int movedFiles;
  final int skippedFiles;
  final int failedFiles;
  final List<QuarantineItem> items;

  /// 稳定错误码，例如 QUARANTINE_SPACE_INSUFFICIENT。
  final String? errorCode;

  bool get isSpaceInsufficient => errorCode == 'QUARANTINE_SPACE_INSUFFICIENT';
}

/// 恢复或清空操作的汇总结果。
class QuarantineActionResult {
  const QuarantineActionResult({
    required this.successCount,
    required this.failedCount,
    required this.bytes,
  });

  final int successCount;
  final int failedCount;
  final int bytes;
}

/// 待隔离的源文件描述，由清理/微信专清在执行前组装。
class QuarantineCandidate {
  const QuarantineCandidate({
    required this.path,
    required this.bytes,
    required this.source,
    required this.category,
    this.retentionDays,
  });

  final String path;
  final int bytes;
  final String source;
  final String category;

  /// 覆盖默认保留天数；为空则使用设置中的 quarantineDays。
  final int? retentionDays;
}

/// 本地隔离引擎：负责选择非 C 盘根目录、移入、索引、恢复与到期清理。
///
/// V1 用 JSON 索引持久化（后续可迁 SQLite），隔离文件本体放在用户选择或自动探测的目录。
class QuarantineService {
  QuarantineService({
    Map<String, String>? environment,
    this.defaultRetentionDays = 7,
    String? configuredRoot,
  }) : _environment = environment ?? Platform.environment,
       _configuredRoot = configuredRoot;

  final Map<String, String> _environment;
  final int defaultRetentionDays;
  final String? _configuredRoot;

  /// 解析可用的隔离根目录；优先用户配置，其次非 C 盘，最后回退到用户文档。
  Future<Directory> resolveRoot() async {
    final configured = _configuredRoot?.trim();
    if (configured != null && configured.isNotEmpty) {
      final dir = Directory(configured);
      await dir.create(recursive: true);
      return dir;
    }

    final auto = await _preferNonSystemDriveRoot();
    if (auto != null) {
      await auto.create(recursive: true);
      return auto;
    }

    final documents =
        _environment['USERPROFILE'] != null
            ? Directory(
              '${_environment['USERPROFILE']}\\Documents\\CDriveManagerQuarantine',
            )
            : Directory('CDriveManagerQuarantine');
    await documents.create(recursive: true);
    return documents;
  }

  Future<List<QuarantineItem>> listItems() async {
    final index = await _loadIndex();
    index.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return index;
  }

  Future<int> totalBytes() async {
    final items = await listItems();
    return items.fold<int>(0, (sum, item) => sum + item.bytes);
  }

  /// 将候选文件移入隔离区；空间不足时拒绝并返回错误码，禁止自动永久删除。
  Future<QuarantineMoveResult> quarantineFiles(
    Iterable<QuarantineCandidate> candidates, {
    bool Function()? shouldCancel,
    void Function(double progress, int movedBytes)? onProgress,
  }) async {
    final list = _dedupeByPath(candidates).toList();
    final needed = list.fold<int>(0, (sum, item) => sum + item.bytes);
    final root = await resolveRoot();

    if (!await _hasEnoughSpace(root, needed)) {
      return const QuarantineMoveResult(
        movedBytes: 0,
        movedFiles: 0,
        skippedFiles: 0,
        failedFiles: 0,
        items: [],
        errorCode: 'QUARANTINE_SPACE_INSUFFICIENT',
      );
    }

    final index = await _loadIndex();
    final created = <QuarantineItem>[];
    var movedBytes = 0;
    var movedFiles = 0;
    var skippedFiles = 0;
    var failedFiles = 0;

    onProgress?.call(0, 0);
    for (var i = 0; i < list.length; i++) {
      final candidate = list[i];
      if (shouldCancel?.call() ?? false) {
        skippedFiles++;
        onProgress?.call((i + 1) / list.length, movedBytes);
        continue;
      }

      try {
        final source = File(candidate.path);
        if (!await source.exists()) {
          skippedFiles++;
          onProgress?.call((i + 1) / list.length, movedBytes);
          continue;
        }

        final item = await _moveOne(source, candidate, root);
        created.add(item);
        index.add(item);
        movedBytes += item.bytes;
        movedFiles++;
      } on FileSystemException {
        failedFiles++;
      } on Object {
        failedFiles++;
      }
      onProgress?.call((i + 1) / list.length, movedBytes);
    }

    await _saveIndex(index);
    return QuarantineMoveResult(
      movedBytes: movedBytes,
      movedFiles: movedFiles,
      skippedFiles: skippedFiles,
      failedFiles: failedFiles,
      items: created,
    );
  }

  /// 按隔离记录恢复到原路径；若原路径父目录缺失则自动创建。
  Future<QuarantineActionResult> restoreItems(
    Iterable<QuarantineItem> items, {
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
  }) async {
    final list = items.toList();
    final index = await _loadIndex();
    var success = 0;
    var failed = 0;
    var bytes = 0;

    onProgress?.call(0);
    for (var i = 0; i < list.length; i++) {
      if (shouldCancel?.call() ?? false) break;
      final item = list[i];
      try {
        final quarantined = File(item.quarantinePath);
        if (!await quarantined.exists()) {
          failed++;
          onProgress?.call((i + 1) / list.length);
          continue;
        }
        final target = File(item.originalPath);
        await target.parent.create(recursive: true);
        if (await target.exists()) {
          // 原路径已有文件时不覆盖，避免误伤用户后来写入的内容。
          failed++;
          onProgress?.call((i + 1) / list.length);
          continue;
        }
        await quarantined.copy(target.path);
        await quarantined.delete();
        index.removeWhere((entry) => entry.id == item.id);
        success++;
        bytes += item.bytes;
      } on Object {
        failed++;
      }
      onProgress?.call((i + 1) / list.length);
    }

    await _saveIndex(index);
    return QuarantineActionResult(
      successCount: success,
      failedCount: failed,
      bytes: bytes,
    );
  }

  /// 永久删除已选隔离项（用户主动清空，不是自动删未到期项）。
  Future<QuarantineActionResult> purgeItems(
    Iterable<QuarantineItem> items, {
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
  }) async {
    final list = items.toList();
    final index = await _loadIndex();
    var success = 0;
    var failed = 0;
    var bytes = 0;

    onProgress?.call(0);
    for (var i = 0; i < list.length; i++) {
      if (shouldCancel?.call() ?? false) break;
      final item = list[i];
      try {
        final file = File(item.quarantinePath);
        if (await file.exists()) {
          await file.delete();
        }
        index.removeWhere((entry) => entry.id == item.id);
        success++;
        bytes += item.bytes;
      } on Object {
        failed++;
      }
      onProgress?.call((i + 1) / list.length);
    }

    await _saveIndex(index);
    return QuarantineActionResult(
      successCount: success,
      failedCount: failed,
      bytes: bytes,
    );
  }

  /// 仅清理已到期且索引完整的项，满足 PRD「自动清理只删到期项」。
  Future<QuarantineActionResult> purgeExpired({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final expired =
        (await listItems())
            .where((item) => item.statusAt(moment) == QuarantineStatus.expired)
            .toList();
    return purgeItems(expired);
  }

  Future<void> openQuarantineFolder() async {
    final root = await resolveRoot();
    await Process.start('explorer', [root.path]);
  }

  Future<QuarantineItem> _moveOne(
    File source,
    QuarantineCandidate candidate,
    Directory root,
  ) async {
    final now = DateTime.now();
    final retention = candidate.retentionDays ?? defaultRetentionDays;
    final dayFolder = Directory(
      '${root.path}\\items\\${_formatDay(now)}',
    );
    await dayFolder.create(recursive: true);

    final id =
        '${now.microsecondsSinceEpoch}_${source.path.hashCode.abs().toRadixString(16)}';
    final safeName = _safeFileName(source.uri.pathSegments.isEmpty
        ? 'file'
        : source.uri.pathSegments.last);
    final targetPath = '${dayFolder.path}\\${id}_$safeName';
    final target = File(targetPath);

    // 跨盘时 copy+delete；同盘 rename 更快且保留原子性。
    final sameVolume =
        _driveLetter(source.path)?.toUpperCase() ==
        _driveLetter(targetPath)?.toUpperCase();
    if (sameVolume) {
      await source.rename(targetPath);
    } else {
      await source.copy(targetPath);
      await source.delete();
    }

    final stat = await target.stat();
    return QuarantineItem(
      id: id,
      originalPath: candidate.path,
      quarantinePath: targetPath,
      bytes: candidate.bytes > 0 ? candidate.bytes : stat.size,
      fingerprint: _fingerprint(candidate.path, stat.size, stat.modified),
      source: candidate.source,
      category: candidate.category,
      displayName: safeName,
      createdAt: now,
      expireAt: now.add(Duration(days: retention.clamp(1, 30))),
    );
  }

  Future<Directory?> _preferNonSystemDriveRoot() async {
    final drives = await _listFixedDrives();
    for (final drive in drives) {
      if (drive.toUpperCase().startsWith('C:')) continue;
      final candidate = Directory('$drive\\CDriveManagerQuarantine');
      try {
        await candidate.create(recursive: true);
        // 写探测，避免选到只读或权限不足的盘。
        final probe = File('${candidate.path}\\.write_probe');
        await probe.writeAsString('ok');
        await probe.delete();
        return candidate;
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<List<String>> _listFixedDrives() async {
    final result = await Process.run('wmic', [
      'logicaldisk',
      'where',
      'DriveType=3',
      'get',
      'DeviceID',
    ]);
    if (result.exitCode != 0) return const [];
    final lines =
        (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => RegExp(r'^[A-Za-z]:$').hasMatch(line))
            .toList();
    return lines;
  }

  Future<bool> _hasEnoughSpace(Directory root, int neededBytes) async {
    final drive = _driveLetter(root.path);
    if (drive == null) return true;
    final free = await _freeBytesOnDrive(drive);
    if (free == null) return true;
    // 预留 200MB 缓冲，避免把隔离盘写满。
    const buffer = 200 * 1024 * 1024;
    return free > neededBytes + buffer;
  }

  Future<int?> _freeBytesOnDrive(String drive) async {
    final result = await Process.run('wmic', [
      'logicaldisk',
      'where',
      "DeviceID='$drive'",
      'get',
      'FreeSpace',
      '/value',
    ]);
    if (result.exitCode != 0) return null;
    final match = RegExp(
      r'FreeSpace=(\d+)',
    ).firstMatch(result.stdout as String);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<List<QuarantineItem>> _loadIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return <QuarantineItem>[];
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return <QuarantineItem>[];
      final raw = json['items'];
      if (raw is! List) return <QuarantineItem>[];
      return raw
          .whereType<Map>()
          .map(
            (item) => QuarantineItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
    } on Object {
      return <QuarantineItem>[];
    }
  }

  Future<void> _saveIndex(List<QuarantineItem> items) async {
    final file = await _indexFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<File> _indexFile() async {
    final appData =
        _environment['APPDATA'] ??
        '${_environment['USERPROFILE']}\\AppData\\Roaming';
    return File('$appData\\CDriveManager\\quarantine_index.json');
  }

  Iterable<QuarantineCandidate> _dedupeByPath(
    Iterable<QuarantineCandidate> candidates,
  ) {
    final seen = <String>{};
    return candidates.where((item) {
      final key = item.path.replaceAll('/', r'\').toLowerCase();
      return seen.add(key);
    });
  }

  String _fingerprint(String path, int bytes, DateTime modified) {
    // V1 用路径+大小+mtime 作为索引完整性指纹，避免整文件哈希拖慢大批量移入。
    return '$bytes:${modified.millisecondsSinceEpoch}:${path.toLowerCase()}';
  }

  String _safeFileName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (sanitized.isEmpty) return 'file.bin';
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }

  String _formatDay(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String? _driveLetter(String path) {
    final match = RegExp(r'^([A-Za-z]:)').firstMatch(path);
    return match?.group(1);
  }
}

String formatQuarantineBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final precision = unit <= 1 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unit]}';
}

String quarantineStatusLabel(QuarantineStatus status) {
  return switch (status) {
    QuarantineStatus.retained => '保留中',
    QuarantineStatus.expiring => '即将到期',
    QuarantineStatus.expired => '已到期',
  };
}
