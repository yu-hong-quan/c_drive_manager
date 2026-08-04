import 'dart:convert';
import 'dart:io';

/// Persisted application settings for the desktop client.
class AppSettings {
  const AppSettings({
    required this.launchOnStartup,
    required this.minimizeToTray,
    required this.quarantineDays,
    required this.quarantinePath,
    required this.scanMode,
    required this.skipLargeFiles,
    required this.gameMode,
    required this.hideSensitivePaths,
    required this.localLogsOnly,
    required this.updateChannel,
    required this.autoCheckRules,
    required this.themeMode,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      launchOnStartup: false,
      minimizeToTray: true,
      quarantineDays: 7,
      // 空字符串表示自动选择非 C 盘隔离根目录。
      quarantinePath: '',
      scanMode: 'balanced',
      skipLargeFiles: true,
      gameMode: false,
      hideSensitivePaths: true,
      localLogsOnly: true,
      updateChannel: 'stable',
      autoCheckRules: false,
      themeMode: 'light',
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      launchOnStartup:
          json['launchOnStartup'] as bool? ?? defaults.launchOnStartup,
      minimizeToTray:
          json['minimizeToTray'] as bool? ?? defaults.minimizeToTray,
      quarantineDays: _readInt(json['quarantineDays'], defaults.quarantineDays),
      quarantinePath:
          json['quarantinePath'] as String? ?? defaults.quarantinePath,
      scanMode: json['scanMode'] as String? ?? defaults.scanMode,
      skipLargeFiles:
          json['skipLargeFiles'] as bool? ?? defaults.skipLargeFiles,
      gameMode: json['gameMode'] as bool? ?? defaults.gameMode,
      hideSensitivePaths:
          json['hideSensitivePaths'] as bool? ?? defaults.hideSensitivePaths,
      localLogsOnly: json['localLogsOnly'] as bool? ?? defaults.localLogsOnly,
      updateChannel: json['updateChannel'] as String? ?? defaults.updateChannel,
      autoCheckRules:
          json['autoCheckRules'] as bool? ?? defaults.autoCheckRules,
      themeMode: json['themeMode'] as String? ?? defaults.themeMode,
    );
  }

  final bool launchOnStartup;
  final bool minimizeToTray;
  final int quarantineDays;

  /// 用户指定的隔离根目录；为空时由隔离服务自动探测非 C 盘。
  final String quarantinePath;
  final String scanMode;
  final bool skipLargeFiles;
  final bool gameMode;
  final bool hideSensitivePaths;
  final bool localLogsOnly;
  final String updateChannel;
  final bool autoCheckRules;
  final String themeMode;

  AppSettings copyWith({
    bool? launchOnStartup,
    bool? minimizeToTray,
    int? quarantineDays,
    String? quarantinePath,
    String? scanMode,
    bool? skipLargeFiles,
    bool? gameMode,
    bool? hideSensitivePaths,
    bool? localLogsOnly,
    String? updateChannel,
    bool? autoCheckRules,
    String? themeMode,
  }) {
    return AppSettings(
      launchOnStartup: launchOnStartup ?? this.launchOnStartup,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      quarantineDays: quarantineDays ?? this.quarantineDays,
      quarantinePath: quarantinePath ?? this.quarantinePath,
      scanMode: scanMode ?? this.scanMode,
      skipLargeFiles: skipLargeFiles ?? this.skipLargeFiles,
      gameMode: gameMode ?? this.gameMode,
      hideSensitivePaths: hideSensitivePaths ?? this.hideSensitivePaths,
      localLogsOnly: localLogsOnly ?? this.localLogsOnly,
      updateChannel: updateChannel ?? this.updateChannel,
      autoCheckRules: autoCheckRules ?? this.autoCheckRules,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'launchOnStartup': launchOnStartup,
      'minimizeToTray': minimizeToTray,
      'quarantineDays': quarantineDays,
      'quarantinePath': quarantinePath,
      'scanMode': scanMode,
      'skipLargeFiles': skipLargeFiles,
      'gameMode': gameMode,
      'hideSensitivePaths': hideSensitivePaths,
      'localLogsOnly': localLogsOnly,
      'updateChannel': updateChannel,
      'autoCheckRules': autoCheckRules,
      'themeMode': themeMode,
    };
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}

/// Stores settings under APPDATA so preferences survive app restarts.
class SettingsService {
  Future<AppSettings> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) return AppSettings.defaults();
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } on Object {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  Future<File> _settingsFile() async {
    final appData =
        Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    return File('$appData\\CDriveManager\\settings.json');
  }
}
