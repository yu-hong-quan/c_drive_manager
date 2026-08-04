import 'dart:convert';
import 'dart:io';

import '../../native/native_bridge.dart';

/// 隔离项状态：保留中 / 即将到期 / 已到期待清理。
enum QuarantineStatus { retained, expiring, expired }

/// 单条隔离记录。
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
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expireAt:
          DateTime.tryParse(json['expireAt'] as String? ?? '') ??
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
    if (expireAt.difference(now).inHours <= 48) {
      return QuarantineStatus.expiring;
    }
    return QuarantineStatus.retained;
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

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
  final String? errorCode;

  bool get isSpaceInsufficient => errorCode == 'QUARANTINE_SPACE_INSUFFICIENT';
}

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
  final int? retentionDays;
}

/// 隔离服务：默认通过 Rust FFI 执行，DLL 不可用时回退到本地 JSON 索引实现。
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

  Map<String, dynamic> get _baseRequest => {
    'quarantineDays': defaultRetentionDays,
    if ((_configuredRoot ?? '').trim().isNotEmpty)
      'quarantinePath': _configuredRoot,
  };

  Future<Directory> resolveRoot() async {
    if (NativeBridge.isAvailable) {
      final raw = NativeBridge.instance.call('quarantine.resolve_root', _baseRequest);
      return Directory(raw['path']?.toString() ?? '');
    }
    return _resolveRootDart();
  }

  Future<List<QuarantineItem>> listItems() async {
    if (NativeBridge.isAvailable) {
      final raw = NativeBridge.instance.call('quarantine.list', _baseRequest) as List<dynamic>;
      return raw
          .map((item) => QuarantineItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return _loadIndexDart();
  }

  Future<QuarantineMoveResult> quarantineFiles(
    Iterable<QuarantineCandidate> candidates, {
    bool Function()? shouldCancel,
    void Function(double progress, int movedBytes)? onProgress,
  }) async {
    final list = candidates.toList();
    if (NativeBridge.isAvailable) {
      onProgress?.call(0.05, 0);
      final raw = NativeBridge.instance.call('quarantine.move', {
        ..._baseRequest,
        'candidates': [
          for (final item in list)
            {
              'path': item.path,
              'bytes': item.bytes,
              'source': item.source,
              'category': item.category,
              if (item.retentionDays != null) 'retentionDays': item.retentionDays,
            },
        ],
      });
      final movedBytes = (raw['movedBytes'] as num?)?.toInt() ?? 0;
      onProgress?.call(1, movedBytes);
      final items =
          (raw['items'] as List? ?? const [])
              .map((item) => QuarantineItem.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
      return QuarantineMoveResult(
        movedBytes: movedBytes,
        movedFiles: (raw['movedFiles'] as num?)?.toInt() ?? 0,
        skippedFiles: (raw['skippedFiles'] as num?)?.toInt() ?? 0,
        failedFiles: (raw['failedFiles'] as num?)?.toInt() ?? 0,
        items: items,
        errorCode: raw['errorCode']?.toString(),
      );
    }
    // 极端回退：直接删除不可恢复；此处仅返回空间不足提示，避免误删。
    return const QuarantineMoveResult(
      movedBytes: 0,
      movedFiles: 0,
      skippedFiles: 0,
      failedFiles: 0,
      items: [],
      errorCode: 'ENGINE_UNAVAILABLE',
    );
  }

  Future<QuarantineActionResult> restoreItems(
    Iterable<QuarantineItem> items, {
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
  }) async {
    if (!NativeBridge.isAvailable) {
      return const QuarantineActionResult(successCount: 0, failedCount: 0, bytes: 0);
    }
    onProgress?.call(0.05);
    final raw = NativeBridge.instance.call('quarantine.restore', {
      ..._baseRequest,
      'ids': [for (final item in items) item.id],
    });
    onProgress?.call(1);
    return QuarantineActionResult(
      successCount: (raw['successCount'] as num?)?.toInt() ?? 0,
      failedCount: (raw['failedCount'] as num?)?.toInt() ?? 0,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<QuarantineActionResult> purgeItems(
    Iterable<QuarantineItem> items, {
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
  }) async {
    if (!NativeBridge.isAvailable) {
      return const QuarantineActionResult(successCount: 0, failedCount: 0, bytes: 0);
    }
    onProgress?.call(0.05);
    final raw = NativeBridge.instance.call('quarantine.purge', {
      ..._baseRequest,
      'ids': [for (final item in items) item.id],
    });
    onProgress?.call(1);
    return QuarantineActionResult(
      successCount: (raw['successCount'] as num?)?.toInt() ?? 0,
      failedCount: (raw['failedCount'] as num?)?.toInt() ?? 0,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<QuarantineActionResult> purgeExpired({DateTime? now}) async {
    if (!NativeBridge.isAvailable) {
      return const QuarantineActionResult(successCount: 0, failedCount: 0, bytes: 0);
    }
    final raw = NativeBridge.instance.call('quarantine.purge_expired', _baseRequest);
    return QuarantineActionResult(
      successCount: (raw['successCount'] as num?)?.toInt() ?? 0,
      failedCount: (raw['failedCount'] as num?)?.toInt() ?? 0,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> openQuarantineFolder() async {
    if (NativeBridge.isAvailable) {
      NativeBridge.instance.call('quarantine.open_folder', _baseRequest);
      return;
    }
    final root = await resolveRoot();
    await Process.start('explorer', [root.path]);
  }

  Future<Directory> _resolveRootDart() async {
    final configured = _configuredRoot?.trim();
    if (configured != null && configured.isNotEmpty) {
      final dir = Directory(configured);
      await dir.create(recursive: true);
      return dir;
    }
    final documents = Directory(
      '${_environment['USERPROFILE']}\\Documents\\CDriveManagerQuarantine',
    );
    await documents.create(recursive: true);
    return documents;
  }

  Future<List<QuarantineItem>> _loadIndexDart() async {
    final appData =
        _environment['APPDATA'] ??
        '${_environment['USERPROFILE']}\\AppData\\Roaming';
    final file = File('$appData\\CDriveManager\\quarantine_index.json');
    if (!await file.exists()) return const [];
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final raw = json['items'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => QuarantineItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      return const [];
    }
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
