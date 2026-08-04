import 'dart:io';

import '../../native/native_bridge.dart';
import '../quarantine/quarantine_service.dart';

/// 微信专清风险等级。
enum WechatRisk { safe, caution, high, critical }

class WechatAccount {
  const WechatAccount({
    required this.id,
    required this.displayName,
    required this.rootPath,
    required this.layout,
  });

  factory WechatAccount.fromJson(Map<String, dynamic> json) {
    return WechatAccount(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      rootPath: json['rootPath']?.toString() ?? '',
      layout: json['layout']?.toString() ?? 'classic',
    );
  }

  final String id;
  final String displayName;
  final String rootPath;
  final String layout;

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'rootPath': rootPath,
    'layout': layout,
  };
}

class WechatCategoryRule {
  const WechatCategoryRule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.risk,
    required this.defaultSelected,
    required this.recoverable,
    required this.retentionDays,
    this.allowClean = true,
    this.relativeRoots = const [],
  });

  factory WechatCategoryRule.fromJson(Map<String, dynamic> json) {
    return WechatCategoryRule(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      risk: _riskFrom(json['risk']?.toString()),
      defaultSelected: json['defaultSelected'] == true,
      recoverable: json['recoverable'] == true,
      retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 7,
      allowClean: json['allowClean'] != false,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final WechatRisk risk;
  final bool defaultSelected;
  final bool recoverable;
  final int retentionDays;
  final bool allowClean;
  final List<String> relativeRoots;

  static WechatRisk _riskFrom(String? value) {
    return switch (value) {
      'caution' => WechatRisk.caution,
      'high' => WechatRisk.high,
      'critical' => WechatRisk.critical,
      _ => WechatRisk.safe,
    };
  }
}

class WechatFileItem {
  const WechatFileItem({
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

class WechatCategoryResult {
  const WechatCategoryResult({
    required this.rule,
    required this.accountId,
    required this.bytes,
    required this.fileCount,
    required this.files,
    required this.skipped,
  });

  final WechatCategoryRule rule;
  final String accountId;
  final int bytes;
  final int fileCount;
  final List<WechatFileItem> files;
  final int skipped;

  bool get hasFiles => fileCount > 0;
}

class WechatCleanResult {
  const WechatCleanResult({
    required this.quarantinedBytes,
    required this.quarantinedFiles,
    required this.deletedBytes,
    required this.deletedFiles,
    required this.skippedFiles,
    required this.failedFiles,
    this.errorCode,
  });

  final int quarantinedBytes;
  final int quarantinedFiles;
  final int deletedBytes;
  final int deletedFiles;
  final int skippedFiles;
  final int failedFiles;
  final String? errorCode;

  bool get isBlockedByWechat => errorCode == 'WX_RUNNING';
  bool get isSpaceInsufficient =>
      errorCode == 'QUARANTINE_SPACE_INSUFFICIENT';
}

/// 微信专清服务：默认走 Rust FFI。
class WechatService {
  WechatService();

  Future<List<WechatAccount>> discoverAccounts() async {
    if (!NativeBridge.isAvailable) return const [];
    final raw = NativeBridge.instance.call('wechat.discover') as List<dynamic>;
    return raw
        .map((item) => WechatAccount.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<WechatAccount?> validateCustomRoot(String path) async {
    if (!NativeBridge.isAvailable) return null;
    final raw = NativeBridge.instance.call('wechat.validate_root', {'path': path});
    if (raw == null) return null;
    return WechatAccount.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<bool> isWeChatRunning() async {
    if (!NativeBridge.isAvailable) {
      for (final image in const ['WeChat.exe', 'Weixin.exe']) {
        final result = await Process.run('tasklist', [
          '/FI',
          'IMAGENAME eq $image',
          '/FO',
          'CSV',
          '/NH',
        ]);
        if ((result.stdout as String).toLowerCase().contains(image.toLowerCase())) {
          return true;
        }
      }
      return false;
    }
    final raw = NativeBridge.instance.call('wechat.is_running');
    return raw['running'] == true;
  }

  Future<List<WechatCategoryResult>> scanAccount(
    WechatAccount account, {
    bool Function()? shouldCancel,
    void Function(String ruleId)? onRuleStarted,
    void Function(double progress)? onProgress,
  }) async {
    if (!NativeBridge.isAvailable) return const [];
    onProgress?.call(0.05);
    final raw = NativeBridge.instance.call('wechat.scan', {
      'account': account.toJson(),
    }) as List<dynamic>;
    onProgress?.call(1);
    return raw.map(_categoryFromJson).toList();
  }

  Future<WechatCleanResult> cleanSelected({
    required Iterable<WechatCategoryResult> categories,
    required Set<String> selectedKeys,
    required int quarantineDays,
    String? quarantineRoot,
    bool Function()? shouldCancel,
    void Function(double progress, int processedBytes)? onProgress,
  }) async {
    if (!NativeBridge.isAvailable) {
      return const WechatCleanResult(
        quarantinedBytes: 0,
        quarantinedFiles: 0,
        deletedBytes: 0,
        deletedFiles: 0,
        skippedFiles: 0,
        failedFiles: 0,
        errorCode: 'ENGINE_UNAVAILABLE',
      );
    }

    final selected = <Map<String, dynamic>>[];
    for (final category in categories) {
      for (final file in category.files) {
        final key = selectionKey(category.rule.id, file);
        if (!selectedKeys.contains(key)) continue;
        selected.add({
          'ruleId': category.rule.id,
          'path': file.path,
          'bytes': file.bytes,
          'recoverable': category.rule.recoverable,
          'retentionDays': category.rule.retentionDays,
          'allowClean': category.rule.allowClean,
        });
      }
    }

    onProgress?.call(0.05, 0);
    try {
      final raw = NativeBridge.instance.call('wechat.clean', {
        'accountId': categories.isEmpty ? '' : categories.first.accountId,
        'quarantineDays': quarantineDays,
        if (quarantineRoot != null && quarantineRoot.trim().isNotEmpty)
          'quarantinePath': quarantineRoot,
        'selected': selected,
      });
      final result = WechatCleanResult(
        quarantinedBytes: (raw['quarantinedBytes'] as num?)?.toInt() ?? 0,
        quarantinedFiles: (raw['quarantinedFiles'] as num?)?.toInt() ?? 0,
        deletedBytes: (raw['deletedBytes'] as num?)?.toInt() ?? 0,
        deletedFiles: (raw['deletedFiles'] as num?)?.toInt() ?? 0,
        skippedFiles: (raw['skippedFiles'] as num?)?.toInt() ?? 0,
        failedFiles: (raw['failedFiles'] as num?)?.toInt() ?? 0,
        errorCode: raw['errorCode']?.toString(),
      );
      onProgress?.call(
        1,
        result.quarantinedBytes + result.deletedBytes,
      );
      return result;
    } on NativeApiException catch (error) {
      return WechatCleanResult(
        quarantinedBytes: 0,
        quarantinedFiles: 0,
        deletedBytes: 0,
        deletedFiles: 0,
        skippedFiles: selected.length,
        failedFiles: 0,
        errorCode: error.code,
      );
    }
  }

  static String selectionKey(String ruleId, WechatFileItem file) =>
      '$ruleId::${file.path}';

  WechatCategoryResult _categoryFromJson(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final files =
        (map['files'] as List? ?? const [])
            .map((item) {
              final file = Map<String, dynamic>.from(item as Map);
              return WechatFileItem(
                path: file['path']?.toString() ?? '',
                bytes: (file['bytes'] as num?)?.toInt() ?? 0,
                modified: DateTime.fromMillisecondsSinceEpoch(
                  (file['modifiedMs'] as num?)?.toInt() ?? 0,
                ),
              );
            })
            .toList();
    return WechatCategoryResult(
      rule: WechatCategoryRule.fromJson(
        Map<String, dynamic>.from(map['rule'] as Map),
      ),
      accountId: map['accountId']?.toString() ?? '',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      fileCount: (map['fileCount'] as num?)?.toInt() ?? files.length,
      files: files,
      skipped: (map['skipped'] as num?)?.toInt() ?? 0,
    );
  }
}

String wechatRiskLabel(WechatRisk risk) {
  return switch (risk) {
    WechatRisk.safe => '安全',
    WechatRisk.caution => '谨慎',
    WechatRisk.high => '高风险',
    WechatRisk.critical => '极高风险',
  };
}

String formatWechatBytes(int bytes) => formatQuarantineBytes(bytes);
