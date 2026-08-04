import 'dart:async';
import 'dart:io';

import '../../native/native_bridge.dart';
import '../settings/settings_service.dart';

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
    this.roots = const [],
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

class CleanupExecutionResult {
  const CleanupExecutionResult({
    required this.deletedBytes,
    required this.deletedFiles,
    required this.quarantinedBytes,
    required this.quarantinedFiles,
    required this.skippedFiles,
    required this.failedFiles,
    this.errorCode,
  });

  final int deletedBytes;
  final int deletedFiles;
  final int quarantinedBytes;
  final int quarantinedFiles;
  final int skippedFiles;
  final int failedFiles;
  final String? errorCode;

  bool get isSpaceInsufficient =>
      errorCode == 'QUARANTINE_SPACE_INSUFFICIENT';

  int get releasedBytes => deletedBytes + quarantinedBytes;
}

/// 安全清理服务：优先走 Rust FFI，并把设置透传给引擎。
class CleanupService {
  CleanupService({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  Future<List<CleanupCategoryResult>> scan({
    AppSettings? settings,
    bool Function()? shouldCancel,
    void Function(String ruleId)? onRuleStarted,
    void Function(double progress)? onProgress,
  }) async {
    final prefs = settings ?? AppSettings.defaults();
    if (NativeBridge.isAvailable) {
      onProgress?.call(0.05);
      final raw = NativeBridge.instance.call('cleanup.scan', {
        'scanMode': prefs.scanMode,
        'skipLargeFiles': prefs.skipLargeFiles,
        'gameMode': prefs.gameMode,
      }) as List<dynamic>;
      onProgress?.call(1);
      return raw.map(_categoryFromJson).toList();
    }
    return _scanDart(
      shouldCancel: shouldCancel,
      onRuleStarted: onRuleStarted,
      onProgress: onProgress,
    );
  }

  Future<CleanupExecutionResult> cleanSelected({
    required Iterable<CleanupCategoryResult> categories,
    required Set<String> selectedKeys,
    required AppSettings settings,
    bool Function()? shouldCancel,
    void Function(double progress, int processedBytes)? onProgress,
  }) async {
    final selectedItems = <Map<String, dynamic>>[];
    for (final category in categories) {
      for (final file in category.files) {
        final key = cleanupSelectionKey(category.rule.id, file);
        if (!selectedKeys.contains(key)) continue;
        selectedItems.add({
          'path': file.path,
          'bytes': file.bytes,
          'category': category.rule.id,
          'recoverable': category.rule.recoverable,
          if (category.rule.recoverable) 'retentionDays': settings.quarantineDays,
        });
      }
    }

    if (NativeBridge.isAvailable) {
      onProgress?.call(0.05, 0);
      final raw = NativeBridge.instance.call('cleanup.clean', {
        'items': selectedItems,
        'quarantineDays': settings.quarantineDays,
        if (settings.quarantinePath.trim().isNotEmpty)
          'quarantinePath': settings.quarantinePath,
      });
      final result = CleanupExecutionResult(
        deletedBytes: (raw['deletedBytes'] as num?)?.toInt() ?? 0,
        deletedFiles: (raw['deletedFiles'] as num?)?.toInt() ?? 0,
        quarantinedBytes: (raw['quarantinedBytes'] as num?)?.toInt() ?? 0,
        quarantinedFiles: (raw['quarantinedFiles'] as num?)?.toInt() ?? 0,
        skippedFiles: (raw['skippedFiles'] as num?)?.toInt() ?? 0,
        failedFiles: (raw['failedFiles'] as num?)?.toInt() ?? 0,
        errorCode: raw['errorCode']?.toString(),
      );
      onProgress?.call(1, result.releasedBytes);
      return result;
    }

    return const CleanupExecutionResult(
      deletedBytes: 0,
      deletedFiles: 0,
      quarantinedBytes: 0,
      quarantinedFiles: 0,
      skippedFiles: 0,
      failedFiles: 0,
      errorCode: 'ENGINE_UNAVAILABLE',
    );
  }
  CleanupCategoryResult _categoryFromJson(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final ruleMap = Map<String, dynamic>.from(map['rule'] as Map);
    final files =
        (map['files'] as List? ?? const [])
            .map((item) {
              final file = Map<String, dynamic>.from(item as Map);
              return CleanupFileItem(
                path: file['path']?.toString() ?? '',
                bytes: (file['bytes'] as num?)?.toInt() ?? 0,
                modified: DateTime.fromMillisecondsSinceEpoch(
                  (file['modifiedMs'] as num?)?.toInt() ?? 0,
                ),
              );
            })
            .toList();
    return CleanupCategoryResult(
      rule: CleanupRule(
        id: ruleMap['id']?.toString() ?? '',
        title: ruleMap['title']?.toString() ?? '',
        subtitle: ruleMap['subtitle']?.toString() ?? '',
        source: ruleMap['source']?.toString() ?? '',
        risk: _riskFrom(ruleMap['risk']?.toString()),
        defaultSelected: ruleMap['defaultSelected'] == true,
        recoverable: ruleMap['recoverable'] == true,
      ),
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      fileCount: (map['fileCount'] as num?)?.toInt() ?? files.length,
      files: files,
      skipped: (map['skipped'] as num?)?.toInt() ?? 0,
    );
  }

  CleanupRisk _riskFrom(String? value) {
    return switch (value) {
      'caution' => CleanupRisk.caution,
      'high' => CleanupRisk.high,
      _ => CleanupRisk.safe,
    };
  }

  Future<List<CleanupCategoryResult>> _scanDart({
    bool Function()? shouldCancel,
    void Function(String ruleId)? onRuleStarted,
    void Function(double progress)? onProgress,
  }) async {
    final rules = _dartRules();
    final results = <CleanupCategoryResult>[];
    onProgress?.call(0);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (shouldCancel?.call() ?? false) break;
      onRuleStarted?.call(rule.id);
      final files = <CleanupFileItem>[];
      var bytes = 0;
      var skipped = 0;
      for (final root in rule.roots) {
        if (!await root.exists()) continue;
        try {
          await for (final entity in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (shouldCancel?.call() ?? false) break;
            if (entity is! File) continue;
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
        } on FileSystemException {
          skipped++;
        }
      }
      files.sort((a, b) => b.bytes.compareTo(a.bytes));
      results.add(
        CleanupCategoryResult(
          rule: rule,
          bytes: bytes,
          fileCount: files.length,
          files: files,
          skipped: skipped,
        ),
      );
      onProgress?.call((i + 1) / rules.length);
    }
    return results;
  }

  List<CleanupRule> _dartRules() {
    final tempRoots = [
      _environment['TEMP'],
      _environment['TMP'],
      _join(_environment['WINDIR'], 'Temp'),
    ].whereType<String>().map(Directory.new).toList();
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
    ];
  }

  String? _join(String? root, String child) {
    if (root == null || root.isEmpty) return null;
    final separator = root.endsWith(r'\') ? '' : r'\';
    return '$root$separator$child';
  }
}

String cleanupSelectionKey(String categoryId, CleanupFileItem file) {
  return '$categoryId\u0000${file.path.toLowerCase()}';
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
