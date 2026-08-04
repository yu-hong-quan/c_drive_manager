import 'package:flutter/material.dart';

/// 设计切图资源路径（ASCII 目录，避免中文路径在 Flutter 资源打包时出问题）。
class UiAssets {
  UiAssets._();

  static const logo = 'assets/ui/common/logo.png';
  static const privacyShield = 'assets/ui/common/privacy_shield.png';

  static const navQuarantine = 'assets/ui/nav/quarantine.png';
  static const navSettings = 'assets/ui/nav/settings.png';

  static const cleanupSystem = 'assets/ui/cleanup/system_files.png';
  static const cleanupCache = 'assets/ui/cleanup/app_cache.png';
  static const cleanupRecycle = 'assets/ui/cleanup/recycle_bin.png';
  static const cleanupRecent = 'assets/ui/cleanup/recent_task.png';

  static const wechatRunningCache = 'assets/ui/wechat/running_cache.png';
  static const wechatLogs = 'assets/ui/wechat/logs_updates.png';
  static const wechatImages = 'assets/ui/wechat/chat_images.png';
  static const wechatVideo = 'assets/ui/wechat/chat_video.png';
  static const wechatVoice = 'assets/ui/wechat/voice_audio.png';
  static const wechatFiles = 'assets/ui/wechat/received_files.png';
  static const wechatAccount = 'assets/ui/wechat/account.png';
  static const riskSafe = 'assets/ui/wechat/risk_safe.png';
  static const riskWarning = 'assets/ui/wechat/risk_warning.png';
  static const riskHigh = 'assets/ui/wechat/risk_high.png';

  static const quarantineOpen = 'assets/ui/quarantine/open_folder.png';
  static const quarantineRetained = 'assets/ui/quarantine/retained.png';
  static const quarantineExpiring = 'assets/ui/quarantine/expiring.png';
  static const quarantinePending = 'assets/ui/quarantine/pending.png';
  static const quarantineActive = 'assets/ui/quarantine/active.png';

  static const settingsGeneral = 'assets/ui/settings/general.png';
  static const settingsQuarantine = 'assets/ui/settings/quarantine.png';
  static const settingsScan = 'assets/ui/settings/scan.png';

  static const systemCpu = 'assets/ui/system/cpu.png';
  static const systemMemory = 'assets/ui/system/memory.png';
  static const systemDisk = 'assets/ui/system/disk.png';
  static const systemDisplay = 'assets/ui/system/display.png';
  static const systemWindows = 'assets/ui/system/windows.png';
  static const systemRefresh = 'assets/ui/system/refresh.png';

  static const migrationSafe = 'assets/ui/migration/safe.png';
  static const migrationWarning = 'assets/ui/migration/warning.png';
  static const migrationDisk = 'assets/ui/migration/disk_check.png';

  /// 清理分类图标；无对应切图时返回 null，由调用方回退 Material Icon。
  static String? cleanupCategory(String ruleId) {
    return switch (ruleId) {
      'system_temp' => cleanupSystem,
      'app_cache' => cleanupCache,
      'logs_dumps' => cleanupRecent,
      'recycle_bin' => cleanupRecycle,
      _ => null,
    };
  }

  /// 微信分类图标。
  static String? wechatCategory(String ruleId) {
    return switch (ruleId) {
      'running_cache' => wechatRunningCache,
      'logs_updates' => wechatLogs,
      'chat_images' => wechatImages,
      'chat_video' => wechatVideo,
      'voice_audio' => wechatVoice,
      'received_files' => wechatFiles,
      'stickers_favorites' => wechatImages,
      'chat_database' => wechatAccount,
      _ => null,
    };
  }

  /// 风险等级对应的风险切图。
  static String riskBadge(String risk) {
    return switch (risk) {
      'safe' => riskSafe,
      'caution' || 'warning' => riskWarning,
      _ => riskHigh,
    };
  }
}

/// 优先显示切图，找不到资源时回退到 Material Icon。
class UiAssetIcon extends StatelessWidget {
  const UiAssetIcon({
    super.key,
    required this.asset,
    this.fallback,
    this.size = 28,
    this.color,
  });

  final String? asset;
  final IconData? fallback;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final path = asset;
    if (path != null) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Icon(
      fallback ?? Icons.image_outlined,
      size: size,
      color: color,
    );
  }
}
