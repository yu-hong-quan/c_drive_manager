import 'dart:async';
import 'dart:io';

/// Risk levels used by the cleanup planner and UI confirmation flow.
enum CleanupRisk { safe, caution, high }

/// A bounded cleanup rule with explicit roots and a user-facing explanation.
class CleanupRule {
  const CleanupRule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.source,
    required this.risk,
    required this.defaultSelected,
    required this.recoverable,
    required this.roots,
  });

  final String id;
  final String title;
  final String subtitle;
  final String source;
  final CleanupRisk risk;
  final bool defaultSelected;
  final bool recoverable;
  final List<Directory> roots;
}

/// A concrete file matched by a cleanup rule and shown in the detail drawer.
class CleanupFileItem {
  const CleanupFileItem({
    required this.path,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final int bytes;
  final DateTime modified;

  String get name {
    final normalized = path.replaceAll('/', r'\');
    final index = normalized.lastIndexOf(r'\');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

/// Scan result for one cleanup rule, including the concrete files to delete.
class CleanupCategoryResult {
  const CleanupCategoryResult({
    required this.rule,
    required this.bytes,
    required this.fileCount,
    required this.files,
    required this.skipped,
  });

  final CleanupRule rule;
  final int bytes;
  final int fileCount;
  final List<CleanupFileItem> files;
  final int skipped;

  bool get hasFiles => fileCount > 0;
}

/// Result summary after attempting to clean selected files.
class CleanupExecutionResult {
  const CleanupExecutionResult({
    required this.deletedBytes,
    required this.deletedFiles,
    required this.skippedFiles,
    required this.failedFiles,
  });

  final int deletedBytes;
  final int deletedFiles;
  final int skippedFiles;
  final int failedFiles;
}

/// Local Windows cleanup scanner that only traverses explicit, bounded roots.
class CleanupService {
  CleanupService({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  List<CleanupRule> buildRules() {
    final tempRoots = _directories([
      _environment['TEMP'],
      _environment['TMP'],
      _join(_environment['WINDIR'], 'Temp'),
    ]);
    final localAppData = _environment['LOCALAPPDATA'];
    final programData = _environment['PROGRAMDATA'];

    return [
      CleanupRule(
        id: 'system_temp',
        title: '系统临时文件',
        subtitle: 'Windows 和当前用户产生的临时文件，锁定文件会自动跳过。',
        source: '%TEMP%、%WINDIR%\\Temp',
        risk: CleanupRisk.safe,
        defaultSelected: true,
        recoverable: false,
        roots: tempRoots,
      ),
      CleanupRule(
        id: 'app_cache',
        title: '应用与浏览器缓存',
        subtitle: '可重建的 Chrome、Edge、Electron 等本地缓存文件。',
        source: '%LOCALAPPDATA%\\*\\Cache',
        risk: CleanupRisk.safe,
        defaultSelected: true,
        recoverable: false,
        roots: _directories([
          _join(localAppData, r'Google\Chrome\User Data\Default\Cache'),
          _join(localAppData, r'Google\Chrome\User Data\Default\Code Cache'),
          _join(localAppData, r'Microsoft\Edge\User Data\Default\Cache'),
          _join(localAppData, r'Microsoft\Edge\User Data\Default\Code Cache'),
        ]),
      ),
      CleanupRule(
        id: 'logs_dumps',
        title: '日志与崩溃转储',
        subtitle: '崩溃转储、错误报告缓存和旧日志，通常仅用于排查问题。',
        source: 'CrashDumps、Windows Error Reporting',
        risk: CleanupRisk.safe,
        defaultSelected: true,
        recoverable: false,
        roots: _directories([
          _join(localAppData, 'CrashDumps'),
          _join(programData, r'Microsoft\Windows\WER\ReportArchive'),
          _join(programData, r'Microsoft\Windows\WER\ReportQueue'),
        ]),
      ),
      CleanupRule(
        id: 'recycle_bin',
        title: '回收站',
        subtitle: '回收站可能包含用户主动保留的文件，默认不勾选。',
        source: r'C:\$Recycle.Bin',
        risk: CleanupRisk.caution,
        defaultSelected: false,
        recoverable: false,
        roots: _directories([r'C:\$Recycle.Bin']),
      ),
    ];
  }

  Future<List<CleanupCategoryResult>> scan({
    bool Function()? shouldCancel,
    void Function(String ruleId)? onRuleStarted,
    void Function(double progress)? onProgress,
  }) async {
    final results = <CleanupCategoryResult>[];
    final rules = buildRules();
    onProgress?.call(0);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (shouldCancel?.call() ?? false) break;
      onRuleStarted?.call(rule.id);
      final start = i / rules.length;
      final end = (i + 1) / rules.length;
      results.add(
        await _scanRule(
          rule,
          shouldCancel: shouldCancel,
          onProgress: onProgress,
          progressStart: start,
          progressEnd: end,
        ),
      );
      onProgress?.call(end);
    }
    return results;
  }

  Future<CleanupExecutionResult> cleanFiles(
    Iterable<CleanupFileItem> files, {
    bool Function()? shouldCancel,
    void Function(double progress, int deletedBytes)? onProgress,
  }) async {
    final fileList = files.toList();
    var deletedBytes = 0;
    var deletedFiles = 0;
    var skippedFiles = 0;
    var failedFiles = 0;

    onProgress?.call(0, 0);
    for (var i = 0; i < fileList.length; i++) {
      final item = fileList[i];
      if (shouldCancel?.call() ?? false) {
        skippedFiles++;
        onProgress?.call((i + 1) / fileList.length, deletedBytes);
        continue;
      }
      try {
        await File(item.path).delete();
        deletedBytes += item.bytes;
        deletedFiles++;
      } on FileSystemException {
        failedFiles++;
      }
      onProgress?.call((i + 1) / fileList.length, deletedBytes);
    }

    return CleanupExecutionResult(
      deletedBytes: deletedBytes,
      deletedFiles: deletedFiles,
      skippedFiles: skippedFiles,
      failedFiles: failedFiles,
    );
  }

  Future<CleanupCategoryResult> _scanRule(
    CleanupRule rule, {
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final files = <CleanupFileItem>[];
    var bytes = 0;
    var skipped = 0;
    var visited = 0;

    for (final root in rule.roots) {
      if (shouldCancel?.call() ?? false) break;
      if (!await _isSafeScanRoot(root)) continue;
      final stack = <Directory>[root];

      while (stack.isNotEmpty) {
        if (shouldCancel?.call() ?? false) break;
        final current = stack.removeLast();
        try {
          await for (final entity in current.list(followLinks: false)) {
            if (shouldCancel?.call() ?? false) break;
            visited++;
            if (visited % 200 == 0) {
              // File counts are unknown up front, so intra-rule progress uses a
              // monotonic curve that approaches the rule's end without jumping.
              final local = 1 - (1 / (1 + visited / 1600));
              final capped = local.clamp(0.0, 0.92);
              onProgress?.call(
                progressStart + (progressEnd - progressStart) * capped,
              );
              await Future<void>.delayed(Duration.zero);
            }

            if (entity is Link) {
              skipped++;
              continue;
            }
            if (entity is Directory) {
              if (await _isReparsePoint(entity)) {
                skipped++;
              } else {
                stack.add(entity);
              }
              continue;
            }
            if (entity is File) {
              try {
                final stat = await entity.stat();
                bytes += stat.size;
                files.add(
                  CleanupFileItem(
                    path: entity.path,
                    bytes: stat.size,
                    modified: stat.modified,
                  ),
                );
              } on FileSystemException {
                skipped++;
              }
            }
          }
        } on FileSystemException {
          skipped++;
        }
      }
    }

    files.sort((a, b) => b.bytes.compareTo(a.bytes));
    return CleanupCategoryResult(
      rule: rule,
      bytes: bytes,
      fileCount: files.length,
      files: files,
      skipped: skipped,
    );
  }

  Future<bool> _isReparsePoint(Directory directory) async {
    try {
      return (await directory.stat()).type == FileSystemEntityType.link;
    } on FileSystemException {
      return true;
    }
  }

  Future<bool> _isSafeScanRoot(Directory directory) async {
    final path = directory.path.replaceAll('/', r'\').toLowerCase();
    if (!await directory.exists()) return false;
    if (RegExp(r'^[a-z]:\\?$').hasMatch(path)) return false;
    final userProfile = _environment['USERPROFILE']?.toLowerCase();
    return userProfile == null || path != userProfile;
  }

  List<Directory> _directories(List<String?> paths) {
    return paths
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .map((path) => Directory(path))
        .toList();
  }

  String? _join(String? root, String child) {
    if (root == null || root.isEmpty) return null;
    final separator = root.endsWith(r'\') ? '' : r'\';
    return '$root$separator$child';
  }
}

String formatBytes(int bytes) {
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
