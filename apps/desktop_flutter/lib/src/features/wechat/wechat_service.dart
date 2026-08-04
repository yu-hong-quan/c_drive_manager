import 'dart:io';

import '../quarantine/quarantine_service.dart';

/// 微信专清风险等级，与清理模块语义对齐。
enum WechatRisk { safe, caution, high, critical }

/// 单个可识别的微信账号目录（脱敏展示，不读取消息内容）。
class WechatAccount {
  const WechatAccount({
    required this.id,
    required this.displayName,
    required this.rootPath,
    required this.layout,
  });

  final String id;
  final String displayName;
  final String rootPath;

  /// classic = WeChat Files；xwechat = 新版目录结构。
  final String layout;
}

/// 一类微信数据的扫描规则：仅遍历明确根路径，不碰聊天数据库。
class WechatCategoryRule {
  const WechatCategoryRule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.risk,
    required this.defaultSelected,
    required this.recoverable,
    required this.retentionDays,
    required this.relativeRoots,
    this.allowClean = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final WechatRisk risk;
  final bool defaultSelected;
  final bool recoverable;
  final int retentionDays;
  final List<String> relativeRoots;

  /// critical 类（聊天库）只统计占用，不允许清理入口执行。
  final bool allowClean;
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

/// 微信专清服务：账号发现、分类扫描、退出检测、隔离优先清理。
///
/// 硬约束：不读取/展示消息正文与联系人；不修改未知数据库表；critical 类默认不可清理。
class WechatService {
  WechatService({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  List<WechatCategoryRule> buildRules({required String layout}) {
    if (layout == 'xwechat') {
      return _xwechatRules();
    }
    return _classicRules();
  }

  /// 发现本机微信账号目录；无法识别结构的目录会被跳过。
  Future<List<WechatAccount>> discoverAccounts() async {
    final accounts = <WechatAccount>[];
    final roots = _candidateAccountRoots();

    for (final root in roots) {
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final layout = await _detectLayout(entity);
          if (layout == null) continue;
          final name = entity.uri.pathSegments
              .where((part) => part.isNotEmpty)
              .last;
          accounts.add(
            WechatAccount(
              id: '${layout}_${name.toLowerCase()}',
              displayName: _maskAccountName(name),
              rootPath: entity.path,
              layout: layout,
            ),
          );
        }
      } on FileSystemException {
        continue;
      }
    }

    accounts.sort((a, b) => a.displayName.compareTo(b.displayName));
    return accounts;
  }

  /// 校验用户手动指定的微信数据目录是否可识别。
  Future<WechatAccount?> validateCustomRoot(String path) async {
    final dir = Directory(path.trim());
    if (!await dir.exists()) return null;
    final layout = await _detectLayout(dir);
    if (layout == null) return null;
    final name = dir.uri.pathSegments.where((part) => part.isNotEmpty).last;
    return WechatAccount(
      id: 'custom_${name.toLowerCase()}',
      displayName: _maskAccountName(name),
      rootPath: dir.path,
      layout: layout,
    );
  }

  Future<bool> isWeChatRunning() async {
    for (final image in const ['WeChat.exe', 'Weixin.exe']) {
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq $image',
        '/FO',
        'CSV',
        '/NH',
      ]);
      final stdout = (result.stdout as String).toLowerCase();
      if (stdout.contains(image.toLowerCase())) return true;
    }
    return false;
  }

  Future<List<WechatCategoryResult>> scanAccount(
    WechatAccount account, {
    bool Function()? shouldCancel,
    void Function(String ruleId)? onRuleStarted,
    void Function(double progress)? onProgress,
  }) async {
    final rules = buildRules(layout: account.layout);
    final results = <WechatCategoryResult>[];
    onProgress?.call(0);

    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (shouldCancel?.call() ?? false) break;
      onRuleStarted?.call(rule.id);
      final start = i / rules.length;
      final end = (i + 1) / rules.length;
      results.add(
        await _scanRule(
          account: account,
          rule: rule,
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

  /// 清理所选文件：可恢复项进隔离；安全缓存可直接删除；微信运行中禁止写操作。
  Future<WechatCleanResult> cleanSelected({
    required Iterable<WechatCategoryResult> categories,
    required Set<String> selectedKeys,
    required int quarantineDays,
    String? quarantineRoot,
    bool Function()? shouldCancel,
    void Function(double progress, int processedBytes)? onProgress,
  }) async {
    if (await isWeChatRunning()) {
      return const WechatCleanResult(
        quarantinedBytes: 0,
        quarantinedFiles: 0,
        deletedBytes: 0,
        deletedFiles: 0,
        skippedFiles: 0,
        failedFiles: 0,
        errorCode: 'WX_RUNNING',
      );
    }

    final quarantine = QuarantineService(
      environment: _environment,
      defaultRetentionDays: quarantineDays,
      configuredRoot: quarantineRoot,
    );

    final toQuarantine = <QuarantineCandidate>[];
    final toDelete = <WechatFileItem>[];

    for (final category in categories) {
      if (!category.rule.allowClean) continue;
      for (final file in category.files) {
        final key = selectionKey(category.rule.id, file);
        if (!selectedKeys.contains(key)) continue;
        if (category.rule.recoverable) {
          toQuarantine.add(
            QuarantineCandidate(
              path: file.path,
              bytes: file.bytes,
              source: 'wechat',
              category: category.rule.id,
              retentionDays: category.rule.retentionDays,
            ),
          );
        } else {
          toDelete.add(file);
        }
      }
    }

    var quarantinedBytes = 0;
    var quarantinedFiles = 0;
    var deletedBytes = 0;
    var deletedFiles = 0;
    var skippedFiles = 0;
    var failedFiles = 0;
    String? errorCode;

    final totalSteps = toQuarantine.length + toDelete.length;
    var done = 0;
    void report() {
      final progress = totalSteps == 0 ? 1.0 : done / totalSteps;
      onProgress?.call(progress, quarantinedBytes + deletedBytes);
    }

    report();
    if (toQuarantine.isNotEmpty) {
      final move = await quarantine.quarantineFiles(
        toQuarantine,
        shouldCancel: shouldCancel,
        onProgress: (progress, movedBytes) {
          done = (progress * toQuarantine.length).round();
          quarantinedBytes = movedBytes;
          report();
        },
      );
      if (move.isSpaceInsufficient) {
        return WechatCleanResult(
          quarantinedBytes: 0,
          quarantinedFiles: 0,
          deletedBytes: 0,
          deletedFiles: 0,
          skippedFiles: toQuarantine.length + toDelete.length,
          failedFiles: 0,
          errorCode: 'QUARANTINE_SPACE_INSUFFICIENT',
        );
      }
      quarantinedBytes = move.movedBytes;
      quarantinedFiles = move.movedFiles;
      skippedFiles += move.skippedFiles;
      failedFiles += move.failedFiles;
      errorCode = move.errorCode;
      done = toQuarantine.length;
      report();
    }

    for (final file in toDelete) {
      if (shouldCancel?.call() ?? false) {
        skippedFiles++;
        done++;
        report();
        continue;
      }
      try {
        await File(file.path).delete();
        deletedBytes += file.bytes;
        deletedFiles++;
      } on FileSystemException {
        failedFiles++;
      }
      done++;
      report();
    }

    return WechatCleanResult(
      quarantinedBytes: quarantinedBytes,
      quarantinedFiles: quarantinedFiles,
      deletedBytes: deletedBytes,
      deletedFiles: deletedFiles,
      skippedFiles: skippedFiles,
      failedFiles: failedFiles,
      errorCode: errorCode,
    );
  }

  static String selectionKey(String ruleId, WechatFileItem file) =>
      '$ruleId::${file.path}';

  List<WechatCategoryRule> _classicRules() {
    return const [
      WechatCategoryRule(
        id: 'running_cache',
        title: '运行缓存',
        subtitle: '缩略图、临时缓存和可重建资源，清理后可自动再生。',
        risk: WechatRisk.safe,
        defaultSelected: true,
        recoverable: false,
        retentionDays: 3,
        relativeRoots: [
          r'FileStorage\Cache',
          r'FileStorage\Temp',
          r'FileStorage\Image\Thumb',
        ],
      ),
      WechatCategoryRule(
        id: 'logs_updates',
        title: '日志与更新残留',
        subtitle: '本地日志和更新残留，通常仅用于排查问题。',
        risk: WechatRisk.safe,
        defaultSelected: true,
        recoverable: true,
        retentionDays: 3,
        relativeRoots: [r'log', r'Log', r'Update'],
      ),
      WechatCategoryRule(
        id: 'chat_images',
        title: '聊天图片',
        subtitle: '聊天图片属于用户资料，默认不选，清理后进入隔离区。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'FileStorage\Image', r'FileStorage\MsgImg'],
      ),
      WechatCategoryRule(
        id: 'chat_video',
        title: '聊天视频',
        subtitle: '聊天视频体积大，默认不选，清理后隔离保留。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'FileStorage\Video'],
      ),
      WechatCategoryRule(
        id: 'voice_audio',
        title: '语音与音频',
        subtitle: '语音消息缓存，默认不选。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'FileStorage\Voice', r'FileStorage\Audio'],
      ),
      WechatCategoryRule(
        id: 'received_files',
        title: '接收文件',
        subtitle: '聊天接收的文件，默认不选，清理后隔离 7 天。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'FileStorage\File'],
      ),
      WechatCategoryRule(
        id: 'stickers_favorites',
        title: '表情与收藏缓存',
        subtitle: '表情与收藏相关缓存，默认不选。',
        risk: WechatRisk.caution,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [
          r'FileStorage\CustomEmotion',
          r'FileStorage\Favorite',
        ],
      ),
      WechatCategoryRule(
        id: 'chat_database',
        title: '聊天数据库',
        subtitle: '极高风险：仅统计占用，V1 不提供直接删除。',
        risk: WechatRisk.critical,
        defaultSelected: false,
        recoverable: false,
        retentionDays: 7,
        relativeRoots: [r'Msg'],
        allowClean: false,
      ),
    ];
  }

  List<WechatCategoryRule> _xwechatRules() {
    // 新版微信目录命名不完全公开，仅匹配可确认的缓存/附件类相对路径。
    return const [
      WechatCategoryRule(
        id: 'running_cache',
        title: '运行缓存',
        subtitle: '新版微信可重建缓存，默认勾选。',
        risk: WechatRisk.safe,
        defaultSelected: true,
        recoverable: false,
        retentionDays: 3,
        relativeRoots: [r'cache', r'temp', r'radium\cache'],
      ),
      WechatCategoryRule(
        id: 'logs_updates',
        title: '日志与更新残留',
        subtitle: '日志与更新残留，可隔离后清理。',
        risk: WechatRisk.safe,
        defaultSelected: true,
        recoverable: true,
        retentionDays: 3,
        relativeRoots: [r'log', r'logs', r'update'],
      ),
      WechatCategoryRule(
        id: 'chat_images',
        title: '聊天图片',
        subtitle: '高风险用户资料，默认不选。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'msg\attach', r'db_storage\image'],
      ),
      WechatCategoryRule(
        id: 'chat_video',
        title: '聊天视频',
        subtitle: '高风险用户资料，默认不选。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'db_storage\video'],
      ),
      WechatCategoryRule(
        id: 'received_files',
        title: '接收文件',
        subtitle: '接收文件默认不选，清理后隔离。',
        risk: WechatRisk.high,
        defaultSelected: false,
        recoverable: true,
        retentionDays: 7,
        relativeRoots: [r'msg\file', r'db_storage\file'],
      ),
      WechatCategoryRule(
        id: 'chat_database',
        title: '聊天数据库',
        subtitle: '极高风险：仅统计占用，不提供直接删除。',
        risk: WechatRisk.critical,
        defaultSelected: false,
        recoverable: false,
        retentionDays: 7,
        relativeRoots: [r'db_storage', r'msg\db'],
        allowClean: false,
      ),
    ];
  }

  List<Directory> _candidateAccountRoots() {
    final userProfile = _environment['USERPROFILE'];
    final documents = _join(userProfile, 'Documents');
    return _directories([
      _join(documents, 'WeChat Files'),
      _join(documents, 'xwechat_files'),
      _join(_environment['APPDATA'], r'Tencent\WeChat\All Users'),
    ]);
  }

  Future<String?> _detectLayout(Directory accountDir) async {
    final classicMarkers = [
      Directory('${accountDir.path}\\FileStorage'),
      Directory('${accountDir.path}\\Msg'),
    ];
    if (await _anyExists(classicMarkers)) return 'classic';

    final xwechatMarkers = [
      Directory('${accountDir.path}\\db_storage'),
      Directory('${accountDir.path}\\msg'),
      Directory('${accountDir.path}\\cache'),
    ];
    if (await _anyExists(xwechatMarkers)) return 'xwechat';
    return null;
  }

  Future<bool> _anyExists(List<Directory> dirs) async {
    for (final dir in dirs) {
      if (await dir.exists()) return true;
    }
    return false;
  }

  Future<WechatCategoryResult> _scanRule({
    required WechatAccount account,
    required WechatCategoryRule rule,
    bool Function()? shouldCancel,
    void Function(double progress)? onProgress,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final files = <WechatFileItem>[];
    var bytes = 0;
    var skipped = 0;
    var visited = 0;
    final roots = rule.relativeRoots
        .map((relative) => Directory('${account.rootPath}\\$relative'))
        .where((dir) => true)
        .toList();

    for (final root in roots) {
      if (shouldCancel?.call() ?? false) break;
      if (!await root.exists()) continue;
      if (!await _isSafeScanRoot(root, account.rootPath)) continue;

      final stack = <Directory>[root];
      while (stack.isNotEmpty) {
        if (shouldCancel?.call() ?? false) break;
        final current = stack.removeLast();
        try {
          await for (final entity in current.list(followLinks: false)) {
            if (shouldCancel?.call() ?? false) break;
            visited++;
            if (visited % 200 == 0) {
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
              // 聊天库规则只统计体积，仍递归；其他规则跳过明显的数据库目录名。
              final lower = entity.path.toLowerCase();
              if (rule.id != 'chat_database' &&
                  (lower.endsWith(r'\msg') ||
                      lower.contains(r'\msg\multi') ||
                      lower.endsWith(r'\db_storage'))) {
                skipped++;
                continue;
              }
              stack.add(entity);
              continue;
            }
            if (entity is File) {
              // 数据库规则下只统计 .db 等库文件大小，仍不提供删除。
              if (rule.id == 'chat_database') {
                final name = entity.path.toLowerCase();
                if (!(name.endsWith('.db') ||
                    name.endsWith('.db-wal') ||
                    name.endsWith('.db-shm') ||
                    name.endsWith('.db-journal'))) {
                  continue;
                }
              }
              try {
                final stat = await entity.stat();
                bytes += stat.size;
                files.add(
                  WechatFileItem(
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
    return WechatCategoryResult(
      rule: rule,
      accountId: account.id,
      bytes: bytes,
      fileCount: files.length,
      files: files,
      skipped: skipped,
    );
  }

  Future<bool> _isSafeScanRoot(Directory directory, String accountRoot) async {
    final path = directory.path.replaceAll('/', r'\').toLowerCase();
    final root = accountRoot.replaceAll('/', r'\').toLowerCase();
    if (!path.startsWith(root)) return false;
    if (RegExp(r'^[a-z]:\\?$').hasMatch(path)) return false;
    return await directory.exists();
  }

  String _maskAccountName(String raw) {
    if (raw.length <= 4) return '账号 $raw';
    return '账号 ${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
  }

  List<Directory> _directories(List<String?> paths) {
    return paths
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .map(Directory.new)
        .toList();
  }

  String? _join(String? root, String child) {
    if (root == null || root.isEmpty) return null;
    final separator = root.endsWith(r'\') ? '' : r'\';
    return '$root$separator$child';
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
