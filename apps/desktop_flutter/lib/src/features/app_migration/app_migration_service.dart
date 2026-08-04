import 'dart:convert';
import 'dart:io';

import '../../native/elevation_helper.dart';
import '../../native/native_bridge.dart';
import '../system_info/system_info_service.dart';

enum AppCompatibility { movable, caution, unsupported }

/// Desktop app discovered from Windows uninstall registry entries.
class MigratableApp {
  const MigratableApp({
    required this.id,
    required this.name,
    required this.version,
    required this.publisher,
    required this.bitness,
    required this.installPath,
    required this.executablePath,
    required this.sizeBytes,
    required this.running,
    required this.compatibility,
    required this.reasons,
  });

  final String id;
  final String name;
  final String version;
  final String publisher;
  final String bitness;
  final String installPath;
  final String executablePath;
  final int sizeBytes;
  final bool running;
  final AppCompatibility compatibility;
  final List<String> reasons;

  bool get selectable => compatibility != AppCompatibility.unsupported;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'publisher': publisher,
        'bitness': bitness,
        'installPath': installPath,
        'executablePath': executablePath,
        'sizeBytes': sizeBytes,
        'running': running,
        'compatibility': compatibility.name,
        'reasons': reasons,
      };
}

/// Fixed local volume that can be evaluated as a migration target.
class MigrationTargetVolume {
  const MigrationTargetVolume({
    required this.drive,
    required this.fileSystem,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String drive;
  final String fileSystem;
  final int totalBytes;
  final int freeBytes;

  bool get usable =>
      drive.toUpperCase() != 'C:' && fileSystem.toUpperCase() == 'NTFS';

  Map<String, dynamic> toJson() => {
        'drive': drive,
        'fileSystem': fileSystem,
        'totalBytes': totalBytes,
        'freeBytes': freeBytes,
      };
}

/// Stored transaction preview for a migration request.
class MigrationPlan {
  const MigrationPlan({
    required this.id,
    required this.targetDrive,
    required this.apps,
    required this.totalBytes,
    required this.createdAt,
    required this.transactionPath,
  });

  final String id;
  final String targetDrive;
  final List<MigratableApp> apps;
  final int totalBytes;
  final DateTime createdAt;
  final String transactionPath;
}

/// Result shown after the user creates a guarded migration transaction plan.
class MigrationPlanResult {
  const MigrationPlanResult({
    required this.plan,
    required this.blockers,
    required this.warnings,
  });

  final MigrationPlan plan;
  final List<String> blockers;
  final List<String> warnings;
}

/// User-confirmed execution options that must stay outside the immutable plan.
class MigrationRunOptions {
  const MigrationRunOptions({
    required this.targetRootPath,
    this.desktopShortcutAppIds = const {},
  });

  final String targetRootPath;
  final Set<String> desktopShortcutAppIds;
}

/// Progress update emitted while a transaction is moving app directories.
class MigrationProgress {
  const MigrationProgress({required this.value, required this.message});

  final double value;
  final String message;
}

/// Final execution summary for a migration transaction.
class MigrationExecutionResult {
  const MigrationExecutionResult({
    required this.migrated,
    required this.failed,
    required this.messages,
  });

  final List<String> migrated;
  final List<String> failed;
  final List<String> messages;

  bool get hasFailure => failed.isNotEmpty;
}

/// 扫描 C 盘非系统 Win32 应用并创建本地优先事务计划。
/// 优先走 Rust FFI；引擎不可用时回退到 Dart PowerShell / robocopy。
class AppMigrationService {
  Future<List<MigratableApp>> scanApps() async {
    if (NativeBridge.isAvailable) {
      try {
        final payload = _asMap(
          NativeBridge.instance.call('migration.scan_apps'),
        );
        final apps = <MigratableApp>[];
        final seen = <String>{};
        for (final item in _asList(payload['apps'])) {
          final app = _appFromJson(_asMap(item));
          if (app == null) continue;
          final key =
              '${app.name.toLowerCase()}\u0000${app.installPath.toLowerCase()}';
          if (seen.add(key)) apps.add(app);
        }
        apps.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        return apps;
      } on Object {
        // FFI 失败时回退 Dart，保证迁移页仍可用。
      }
    }
    return _scanAppsDart();
  }

  Future<List<MigrationTargetVolume>> scanTargetVolumes() async {
    if (NativeBridge.isAvailable) {
      try {
        final payload = _asMap(
          NativeBridge.instance.call('migration.scan_targets'),
        );
        return _asList(payload['volumes'])
            .map((item) => _volumeFromJson(_asMap(item)))
            .whereType<MigrationTargetVolume>()
            .toList();
      } on Object {
        // 回退 Dart。
      }
    }
    return _scanTargetVolumesDart();
  }

  Future<MigrationPlanResult> createPlan({
    required List<MigratableApp> apps,
    required MigrationTargetVolume target,
  }) async {
    if (NativeBridge.isAvailable) {
      try {
        final raw = _asMap(
          NativeBridge.instance.call('migration.create_plan', {
            'apps': [for (final app in apps) app.toJson()],
            'target': target.toJson(),
          }),
        );
        return _planResultFromJson(raw, appsFallback: apps);
      } on Object {
        // 回退 Dart。
      }
    }
    return _createPlanDart(apps: apps, target: target);
  }

  Future<MigrationExecutionResult> executePlan(
    MigrationPlan plan, {
    String? targetRootPath,
    Set<String> desktopShortcutAppIds = const {},
    void Function(MigrationProgress progress)? onProgress,
  }) async {
    if (NativeBridge.isAvailable) {
      try {
        return await _executePlanNative(
          plan,
          targetRootPath: targetRootPath,
          desktopShortcutAppIds: desktopShortcutAppIds,
          onProgress: onProgress,
        );
      } on Object {
        // 回退 Dart 执行路径。
      }
    }
    return _executePlanDart(
      plan,
      targetRootPath: targetRootPath,
      desktopShortcutAppIds: desktopShortcutAppIds,
      onProgress: onProgress,
    );
  }

  Future<List<MigratableApp>> _scanAppsDart() async {
    final payload = await _runPowerShell(_scanScript);
    final rawApps = _asList(payload['apps']);
    final apps = <MigratableApp>[];
    final seen = <String>{};

    for (final item in rawApps) {
      final app = _appFromJson(_asMap(item));
      if (app == null) continue;
      final key =
          '${app.name.toLowerCase()}\u0000${app.installPath.toLowerCase()}';
      if (seen.add(key)) {
        apps.add(app);
      }
    }
    apps.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return apps;
  }

  Future<List<MigrationTargetVolume>> _scanTargetVolumesDart() async {
    final payload = await _runPowerShell(_volumeScript);
    return _asList(payload['volumes'])
        .map((item) => _volumeFromJson(_asMap(item)))
        .whereType<MigrationTargetVolume>()
        .toList();
  }

  Future<MigrationPlanResult> _createPlanDart({
    required List<MigratableApp> apps,
    required MigrationTargetVolume target,
  }) async {
    final blockers = <String>[];
    final warnings = <String>[];
    final totalBytes = apps.fold<int>(0, (sum, app) => sum + app.sizeBytes);

    if (apps.isEmpty) {
      blockers.add('请选择至少一个可迁移应用');
    }
    if (!target.usable) {
      blockers.add('目标盘必须是非 C 盘的本地固定 NTFS 卷');
    }
    if (target.freeBytes <= totalBytes * 1.15) {
      blockers.add('目标盘剩余空间不足，需预留至少 15% 校验空间');
    }
    if (apps.any((app) => app.running)) {
      warnings.add('存在运行中的应用，执行迁移前需要先正常退出');
    }
    if (apps.any((app) => app.compatibility == AppCompatibility.caution)) {
      warnings.add('包含“需谨慎”应用，执行前应展开查看风险说明');
    }

    final now = DateTime.now();
    final id = 'move-${now.millisecondsSinceEpoch}';
    final file = await _transactionFile(id);
    final plan = MigrationPlan(
      id: id,
      targetDrive: target.drive,
      apps: apps,
      totalBytes: totalBytes,
      createdAt: now,
      transactionPath: file.path,
    );

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'id': id,
        'status': blockers.isEmpty ? 'planned' : 'blocked',
        'createdAt': now.toIso8601String(),
        'targetDrive': target.drive,
        'totalBytes': totalBytes,
        'blockers': blockers,
        'warnings': warnings,
        'apps': [for (final app in apps) app.toJson()],
        // The native mover must follow this ordered transaction recipe so failed
        // migrations can roll back without leaving the original path broken.
        'recipe': [
          'validate-target-volume',
          'request-app-exit',
          'copy-to-target-temp',
          'verify-file-count-size-hash',
          'rename-source-to-backup',
          'create-directory-junction',
          'verify-original-path',
          'mark-backup-for-delayed-cleanup',
        ],
      }),
    );

    return MigrationPlanResult(
      plan: plan,
      blockers: blockers,
      warnings: warnings,
    );
  }

  Future<MigrationExecutionResult> _executePlanNative(
    MigrationPlan plan, {
    String? targetRootPath,
    Set<String> desktopShortcutAppIds = const {},
    void Function(MigrationProgress progress)? onProgress,
  }) async {
    final migrated = <String>[];
    final failed = <String>[];
    final messages = <String>[];
    final helperPath = _resolveHelperPath();

    for (var i = 0; i < plan.apps.length; i++) {
      final app = plan.apps[i];
      final baseProgress = i / plan.apps.length;
      final stepSize = 1 / plan.apps.length;
      onProgress?.call(
        MigrationProgress(
          value: (baseProgress + 0.1 * stepSize).clamp(0.0, 1.0),
          message: '正在迁移 ${app.name}',
        ),
      );

      final data = _asMap(
        NativeBridge.instance.call('migration.execute_app', {
          'planId': plan.id,
          'app': app.toJson(),
          'targetDrive': plan.targetDrive,
          'targetRootPath': targetRootPath,
          'helperPath': helperPath,
        }),
      );
      final success = data['success'] == true;
      final message = _string(data['message'], fallback: app.name);
      if (success) {
        migrated.add(app.name);
        messages.add(message);
        if (desktopShortcutAppIds.contains(app.id)) {
          try {
            final targetPath = _string(data['targetPath']);
            if (targetPath.isNotEmpty) {
              final shortcutPath =
                  await _createDesktopShortcut(app, targetPath);
              messages.add('${app.name} 桌面快捷方式已创建：$shortcutPath');
            }
          } on Object catch (error) {
            messages.add('${app.name} 已迁移，但桌面快捷方式创建失败：$error');
          }
        }
      } else {
        failed.add(app.name);
        messages.add(message);
      }
      onProgress?.call(
        MigrationProgress(
          value: (baseProgress + stepSize).clamp(0.0, 1.0),
          message: success ? '${app.name} 迁移完成' : '${app.name} 迁移失败',
        ),
      );
    }

    try {
      NativeBridge.instance.call('migration.append_log', {
        'transactionPath': plan.transactionPath,
        'migrated': migrated,
        'failed': failed,
        'messages': messages,
      });
    } on Object {
      await _appendExecutionLog(plan, migrated, failed, messages);
    }

    onProgress?.call(const MigrationProgress(value: 1, message: '迁移任务完成'));
    return MigrationExecutionResult(
      migrated: migrated,
      failed: failed,
      messages: messages,
    );
  }

  Future<MigrationExecutionResult> _executePlanDart(
    MigrationPlan plan, {
    String? targetRootPath,
    Set<String> desktopShortcutAppIds = const {},
    void Function(MigrationProgress progress)? onProgress,
  }) async {
    final migrated = <String>[];
    final failed = <String>[];
    final messages = <String>[];
    final targetRootBase = _normalizeTargetRootPath(
      targetRootPath,
      plan.targetDrive,
    );

    for (var i = 0; i < plan.apps.length; i++) {
      final app = plan.apps[i];
      final baseProgress = i / plan.apps.length;
      final stepSize = 1 / plan.apps.length;
      void progress(double inner, String message) {
        onProgress?.call(
          MigrationProgress(
            value: (baseProgress + inner * stepSize).clamp(0.0, 1.0),
            message: message,
          ),
        );
      }

      try {
        progress(0.05, '正在检查 ${app.name}');
        final source = Directory(app.installPath);
        if (!await source.exists()) {
          throw AppMigrationException('原安装目录不存在：${app.installPath}');
        }
        if (await _isAppRunning(app.installPath)) {
          throw AppMigrationException('应用仍在运行，请退出后再迁移：${app.name}');
        }

        final targetRoot = Directory(targetRootBase);
        final targetDir = Directory(
          _joinWindowsPath(
            targetRoot.path,
            _sourceFolderName(app.installPath, app.name),
          ),
        );
        final tempDir = Directory('${targetDir.path}.copying-${plan.id}');
        final backupDir = Directory('${app.installPath}.cdm-backup-${plan.id}');
        if (await targetDir.exists()) {
          throw AppMigrationException('目标目录已存在：${targetDir.path}');
        }
        if (await backupDir.exists()) {
          throw AppMigrationException('备份目录已存在：${backupDir.path}');
        }

        await targetRoot.create(recursive: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }

        progress(0.2, '正在复制 ${app.name}');
        final copyCode = await _robocopy(source.path, tempDir.path);
        if (copyCode > 7) {
          throw AppMigrationException('复制失败，Robocopy 退出码：$copyCode');
        }

        progress(0.55, '正在校验 ${app.name}');
        final sourceStats = await _directoryStats(source);
        final targetStats = await _directoryStats(tempDir);
        if (sourceStats.files != targetStats.files ||
            sourceStats.bytes != targetStats.bytes) {
          throw AppMigrationException(
            '复制校验失败：源 ${sourceStats.files} 个文件 / ${formatBytes(sourceStats.bytes)}，'
            '目标 ${targetStats.files} 个文件 / ${formatBytes(targetStats.bytes)}',
          );
        }

        progress(0.7, '正在创建备份 ${app.name}');
        await source.rename(backupDir.path);
        var targetPromoted = false;
        try {
          await tempDir.rename(targetDir.path);
          targetPromoted = true;
          progress(0.86, '正在建立兼容链接 ${app.name}');
          final linked = await _createJunction(
            app.installPath,
            targetDir.path,
          );
          if (!linked || !await Directory(app.installPath).exists()) {
            throw AppMigrationException('目录联接创建失败：${app.name}');
          }
        } on Object {
          await _rollbackApp(
            app.installPath,
            backupDir,
            targetDir,
            targetPromoted,
          );
          rethrow;
        }

        migrated.add(app.name);
        messages.add('${app.name} 已迁移，备份保留在 ${backupDir.path}');
        if (desktopShortcutAppIds.contains(app.id)) {
          try {
            final shortcutPath = await _createDesktopShortcut(
              app,
              targetDir.path,
            );
            messages.add('${app.name} 桌面快捷方式已创建：$shortcutPath');
          } on Object catch (error) {
            messages.add('${app.name} 已迁移，但桌面快捷方式创建失败：$error');
          }
        }
        progress(1, '${app.name} 迁移完成');
      } on Object catch (error) {
        failed.add(app.name);
        messages.add('${app.name} 迁移失败：$error');
      }
    }

    await _appendExecutionLog(plan, migrated, failed, messages);
    onProgress?.call(const MigrationProgress(value: 1, message: '迁移任务完成'));
    return MigrationExecutionResult(
      migrated: migrated,
      failed: failed,
      messages: messages,
    );
  }

  MigrationPlanResult _planResultFromJson(
    Map<String, dynamic> json, {
    required List<MigratableApp> appsFallback,
  }) {
    final planJson = _asMap(json['plan']);
    final apps = _asList(planJson['apps'])
        .map((item) => _appFromJson(_asMap(item)))
        .whereType<MigratableApp>()
        .toList();
    return MigrationPlanResult(
      plan: MigrationPlan(
        id: _string(planJson['id']),
        targetDrive: _string(planJson['targetDrive']),
        apps: apps.isEmpty ? appsFallback : apps,
        totalBytes: _parseInt(planJson['totalBytes']),
        createdAt: _parseDateTime(planJson['createdAt']),
        transactionPath: _string(planJson['transactionPath']),
      ),
      blockers: _asList(json['blockers']).map((item) => '$item').toList(),
      warnings: _asList(json['warnings']).map((item) => '$item').toList(),
    );
  }

  DateTime _parseDateTime(dynamic value) {
    final text = '$value'.trim();
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    final millis = int.tryParse(text);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.now();
  }

  String? _resolveHelperPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir\\c_manager_helper.exe',
      '${Directory.current.path}\\c_manager_helper.exe',
      '${Directory.current.parent.parent.path}\\target\\release\\c_manager_helper.exe',
      '${Directory.current.parent.parent.path}\\target\\debug\\c_manager_helper.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  MigratableApp? _appFromJson(Map<String, dynamic> json) {
    final name = _string(json['name']);
    final path = _string(json['installPath']);
    if (name.isEmpty || path.isEmpty) return null;
    final reasons = _asList(json['reasons']).map((item) => '$item').toList();
    return MigratableApp(
      id: _string(json['id'], fallback: '$name|$path'),
      name: name,
      version: _string(json['version'], fallback: '未知'),
      publisher: _string(json['publisher'], fallback: '未知发布者'),
      bitness: _string(json['bitness'], fallback: '未知'),
      installPath: path,
      executablePath: _string(json['executablePath']),
      sizeBytes: _parseInt(json['sizeBytes']),
      running: json['running'] == true,
      compatibility: _compatibilityFrom(_string(json['compatibility'])),
      reasons: reasons.isEmpty ? ['未命中明确风险'] : reasons,
    );
  }

  MigrationTargetVolume? _volumeFromJson(Map<String, dynamic> json) {
    final drive = _string(json['drive']);
    if (drive.isEmpty) return null;
    return MigrationTargetVolume(
      drive: drive,
      fileSystem: _string(json['fileSystem'], fallback: '未知'),
      totalBytes: _parseInt(json['totalBytes']),
      freeBytes: _parseInt(json['freeBytes']),
    );
  }

  AppCompatibility _compatibilityFrom(String value) {
    return switch (value) {
      'movable' => AppCompatibility.movable,
      'caution' => AppCompatibility.caution,
      _ => AppCompatibility.unsupported,
    };
  }

  Future<Map<String, dynamic>> _runPowerShell(String script) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw AppMigrationException('应用迁移扫描失败：${result.stderr}');
    }
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  Future<bool> _isAppRunning(String installPath) async {
    final escapedPath = _powerShellSingleQuote(installPath.toLowerCase());
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      "\$path = '$escapedPath'; "
          "\$count = @(Get-CimInstance Win32_Process | Where-Object { "
          "\$_.ExecutablePath -and \$_.ExecutablePath.ToLowerInvariant().StartsWith(\$path) }).Count; "
          'Write-Output \$count',
    ]);
    return (int.tryParse('${result.stdout}'.trim()) ?? 0) > 0;
  }

  Future<int> _robocopy(String source, String target) async {
    final result = await Process.run('robocopy', [
      source,
      target,
      '/E',
      '/COPY:DAT',
      '/DCOPY:DAT',
      '/R:1',
      '/W:1',
      '/XJ',
      '/NFL',
      '/NDL',
      '/NP',
    ]);
    return result.exitCode;
  }

  Future<bool> _createJunction(String linkPath, String targetPath) async {
    try {
      await ElevationHelper().createJunction(
        linkPath: linkPath,
        targetPath: targetPath,
      );
      return true;
    } on ElevationHelperException {
      return false;
    } on Object {
      return false;
    }
  }

  Future<String> _createDesktopShortcut(
    MigratableApp app,
    String targetPath,
  ) async {
    final executable = await _resolveShortcutExecutable(app, targetPath);
    if (executable == null) {
      throw AppMigrationException('未找到可用于创建快捷方式的 exe：${app.name}');
    }
    final desktop = await _desktopDirectory();
    final shortcut = '${desktop.path}\\${_safeFileName(app.name)}.lnk';
    final script = r'''
$shortcutPath = $args[0]
$targetPath = $args[1]
$workingDirectory = $args[2]
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.WorkingDirectory = $workingDirectory
$shortcut.Save()
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
      shortcut,
      executable.path,
      executable.parent.path,
    ]);
    if (result.exitCode != 0) {
      throw AppMigrationException('桌面快捷方式创建失败：${result.stderr}');
    }
    return shortcut;
  }

  Future<File?> _resolveShortcutExecutable(
    MigratableApp app,
    String targetPath,
  ) async {
    final relativeExecutable = _relativeChildPath(
      app.executablePath,
      app.installPath,
    );
    if (relativeExecutable != null) {
      final movedExecutable = File(
        _joinWindowsPath(targetPath, relativeExecutable),
      );
      if (await movedExecutable.exists()) {
        return movedExecutable;
      }
    }
    return _findPrimaryExecutable(Directory(targetPath), app.name);
  }

  Future<File?> _findPrimaryExecutable(
    Directory directory,
    String appName,
  ) async {
    final candidates = <File>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        candidates.add(entity);
      }
    }
    candidates.sort(
      (a, b) =>
          _executableScore(b, appName).compareTo(_executableScore(a, appName)),
    );
    return candidates.firstOrNull;
  }

  int _executableScore(File file, String appName) {
    final fileName = file.uri.pathSegments.last.toLowerCase();
    final fullPath = file.path.toLowerCase();
    final appLower = appName.toLowerCase();
    var score = 1000 - fullPath.split(Platform.pathSeparator).length * 10;
    // Prefer launchable app binaries over uninstallers or helper processes when
    // the registry does not expose a reliable DisplayIcon executable.
    if (fileName.contains(RegExp(r'unins|uninstall|setup|update|helper'))) {
      score -= 300;
    }
    if (appLower.contains('7-zip') && fileName == '7zfm.exe') {
      score += 500;
    }
    final tokens = appLower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 2);
    for (final token in tokens) {
      if (fileName.contains(token)) score += 60;
    }
    if (!fullPath.contains(RegExp(r'\\(bin|app|program|client)\\'))) {
      score += 20;
    }
    return score;
  }

  Future<Directory> _desktopDirectory() async {
    final userProfile = Platform.environment['USERPROFILE'];
    final desktop = Directory('$userProfile\\Desktop');
    if (await desktop.exists()) return desktop;
    return Directory('${Platform.environment['PUBLIC']}\\Desktop');
  }

  Future<void> _rollbackApp(
    String sourcePath,
    Directory backupDir,
    Directory targetDir,
    bool targetPromoted,
  ) async {
    await Process.run('cmd', ['/c', 'rmdir', sourcePath]);
    if (targetPromoted && await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    if (await backupDir.exists() && !await Directory(sourcePath).exists()) {
      await backupDir.rename(sourcePath);
    }
  }

  Future<_DirectoryStats> _directoryStats(Directory directory) async {
    var files = 0;
    var bytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        files++;
        bytes += stat.size;
      } on FileSystemException {
        // Robocopy may skip inaccessible files; the verification then catches
        // the mismatch and prevents replacing the original directory.
      }
    }
    return _DirectoryStats(files: files, bytes: bytes);
  }

  Future<void> _appendExecutionLog(
    MigrationPlan plan,
    List<String> migrated,
    List<String> failed,
    List<String> messages,
  ) async {
    final file = File(plan.transactionPath);
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data['status'] = failed.isEmpty
        ? 'migrated'
        : (migrated.isEmpty ? 'failed' : 'partial');
    data['executedAt'] = DateTime.now().toIso8601String();
    data['migrated'] = migrated;
    data['failed'] = failed;
    data['messages'] = messages;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<File> _transactionFile(String id) async {
    final appData =
        Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    return File('$appData\\CDriveManager\\migration_transactions\\$id.json');
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value == null) return const [];
    return [value];
  }

  int _parseInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _string(dynamic value, {String fallback = ''}) {
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _safeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'app' : sanitized;
  }

  String _sourceFolderName(String installPath, String fallbackName) {
    final normalized = installPath
        .replaceAll('/', '\\')
        .replaceFirst(RegExp(r'\\+$'), '');
    final segments = normalized.split('\\').where((item) => item.isNotEmpty);
    final folderName = segments.isEmpty ? fallbackName : segments.last;
    // Preserve the original install folder name whenever possible; sanitize
    // only as a guard for malformed registry paths that cannot become a folder.
    return _safeFileName(folderName);
  }

  String _normalizeTargetRootPath(String? value, String targetDrive) {
    final drive = targetDrive.endsWith(':') ? targetDrive : '$targetDrive:';
    final raw = (value == null || value.trim().isEmpty)
        ? '$drive\\CDriveManager\\MigratedApps'
        : value.trim().replaceAll('/', '\\');
    final normalized = raw.contains(':') ? raw : _joinWindowsPath(drive, raw);
    final withSlash = normalized.endsWith('\\') ? normalized : normalized;
    if (!withSlash.toLowerCase().startsWith(drive.toLowerCase())) {
      throw AppMigrationException('目标文件夹必须位于 $drive 盘内：$normalized');
    }
    return withSlash;
  }

  String _joinWindowsPath(String root, String child) {
    final normalizedRoot = root.trim().replaceAll('/', '\\');
    final normalizedChild = child.trim().replaceAll('/', '\\');
    if (normalizedRoot.endsWith('\\')) {
      return '$normalizedRoot$normalizedChild';
    }
    return '$normalizedRoot\\$normalizedChild';
  }

  String? _relativeChildPath(String child, String parent) {
    if (child.trim().isEmpty || parent.trim().isEmpty) return null;
    final normalizedChild = child.replaceAll('/', '\\');
    final normalizedParent = parent
        .replaceAll('/', '\\')
        .replaceFirst(RegExp(r'\\+$'), '');
    final childLower = normalizedChild.toLowerCase();
    final parentLower = '$normalizedParent\\'.toLowerCase();
    if (!childLower.startsWith(parentLower)) return null;
    final relative = normalizedChild.substring(parentLower.length);
    return relative.isEmpty ? null : relative;
  }

  String _powerShellSingleQuote(String value) => value.replaceAll("'", "''");
}

class _DirectoryStats {
  const _DirectoryStats({required this.files, required this.bytes});

  final int files;
  final int bytes;
}

class AppMigrationException implements Exception {
  const AppMigrationException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _scanScript = r'''
$ErrorActionPreference = "SilentlyContinue"
$roots = @(
  @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "64 位" },
  @{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "32 位" },
  @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "当前用户" }
)
$processes = Get-CimInstance Win32_Process | Select-Object Name,ExecutablePath
function Normalize-InstallPath($entry) {
  $path = [string]$entry.InstallLocation
  if ([string]::IsNullOrWhiteSpace($path) -and $entry.DisplayIcon) {
    $icon = [string]$entry.DisplayIcon
    $icon = $icon.Trim('"')
    $icon = $icon -replace ',\d+$',''
    if (Test-Path $icon) { $path = Split-Path $icon -Parent }
  }
  if ([string]::IsNullOrWhiteSpace($path)) { return "" }
  $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim('"'))
  if (!(Test-Path $expanded -PathType Container)) { return "" }
  return (Resolve-Path $expanded).Path.TrimEnd('\')
}
function Resolve-ExecutablePath($entry, $installPath) {
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($raw in @($entry.DisplayIcon, $entry.UninstallString)) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $expanded = [Environment]::ExpandEnvironmentVariables([string]$raw)
    $match = [regex]::Match($expanded, '([A-Za-z]:\\[^"]+?\.exe)')
    if ($match.Success) { $paths.Add($match.Groups[1].Value.Trim('"')) }
  }
  foreach ($path in $paths) {
    if ((Test-Path $path -PathType Leaf) -and
        $path.ToLowerInvariant().StartsWith($installPath.ToLowerInvariant()) -and
        !([IO.Path]::GetFileName($path).ToLowerInvariant() -match 'unins|uninstall|setup|update|helper')) {
      return (Resolve-Path $path).Path
    }
  }
  try {
    $name = ([string]$entry.DisplayName).ToLowerInvariant()
    $files = Get-ChildItem -LiteralPath $installPath -Recurse -File -Filter *.exe -Force |
      Sort-Object @{
        Expression = {
          $file = $_.Name.ToLowerInvariant()
          if ($name.Contains("7-zip") -and $file -eq "7zfm.exe") { return 0 }
          if ($file -match 'unins|uninstall|setup|update|helper') { return 8 }
          if ($name.Split(" -_.()[]{}") | Where-Object { $_.Length -ge 2 -and $file.Contains($_) }) { return 1 }
          return 3
        }
      }, @{ Expression = { $_.FullName.Split('\').Count } }, Length
    if ($files) { return $files[0].FullName }
  } catch {}
  return ""
}
function Measure-AppDir($path) {
  try {
    return [int64]((Get-ChildItem -LiteralPath $path -Recurse -File -Force |
      Measure-Object -Property Length -Sum).Sum)
  } catch {
    return 0
  }
}
function Is-CDriveUserAppPath($path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  $lowerPath = $path.ToLowerInvariant()
  if (!$lowerPath.StartsWith("c:\")) { return $false }
  $blockedRoots = @(
    "$env:WINDIR",
    "$env:ProgramData\Microsoft",
    "$env:ProgramFiles\WindowsApps",
    "$env:ProgramFiles\Common Files\Microsoft Shared",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared"
  )
  foreach ($root in $blockedRoots) {
    if (![string]::IsNullOrWhiteSpace($root) -and $lowerPath.StartsWith($root.ToLowerInvariant())) {
      return $false
    }
  }
  return $true
}
function Get-Compatibility($name, $publisher, $path, $uninstall) {
  $reasons = New-Object System.Collections.Generic.List[string]
  $lower = "$name $publisher $path $uninstall".ToLowerInvariant()
  $systemTokens = @(
    "microsoft windows",
    "windows driver",
    "driver package",
    "defender",
    "security update",
    "runtime",
    "redistributable",
    "appx",
    "msix",
    "system32",
    "windowsapps",
    "visual c++"
  )
  foreach ($token in $systemTokens) {
    if ($lower.Contains($token)) {
      $reasons.Add("系统组件、运行库、驱动或商店应用默认不支持迁移")
      return @{ Level = "unsupported"; Reasons = @($reasons) }
    }
  }
  if ($lower.Contains("update") -or $lower.Contains("service") -or $lower.Contains("helper")) {
    $reasons.Add("存在更新器、服务或辅助进程，迁移前需谨慎验证")
    return @{ Level = "caution"; Reasons = @($reasons) }
  }
  $reasons.Add("非系统应用位于 C 盘，可生成迁移计划")
  return @{ Level = "movable"; Reasons = @($reasons) }
}
$apps = foreach ($root in $roots) {
  Get-ItemProperty $root.Path | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.DisplayName) -or $_.SystemComponent -eq 1) { return }
    $path = Normalize-InstallPath $_
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (!(Is-CDriveUserAppPath $path)) { return }
    $compat = Get-Compatibility $_.DisplayName $_.Publisher $path $_.UninstallString
    if ($compat.Level -eq "unsupported") { return }
    $running = @($processes | Where-Object {
      $_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant().StartsWith($path.ToLowerInvariant())
    }).Count -gt 0
    [pscustomobject]@{
      id = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($_.DisplayName)|$path"))
      name = [string]$_.DisplayName
      version = [string]$_.DisplayVersion
      publisher = [string]$_.Publisher
      bitness = [string]$root.Bits
      installPath = $path
      executablePath = Resolve-ExecutablePath $_ $path
      sizeBytes = Measure-AppDir $path
      running = $running
      compatibility = $compat.Level
      reasons = @($compat.Reasons)
    }
  }
}
[pscustomobject]@{ apps = @($apps) } | ConvertTo-Json -Depth 5 -Compress
''';

const _volumeScript = r'''
$volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
  Select-Object DeviceID,FileSystem,Size,FreeSpace
[pscustomobject]@{
  volumes = @($volumes | ForEach-Object {
    [pscustomobject]@{
      drive = [string]$_.DeviceID
      fileSystem = [string]$_.FileSystem
      totalBytes = [int64]$_.Size
      freeBytes = [int64]$_.FreeSpace
    }
  })
} | ConvertTo-Json -Depth 4 -Compress
''';
