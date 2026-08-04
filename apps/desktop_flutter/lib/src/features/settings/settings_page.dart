import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/ui_assets.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_card.dart';
import 'settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _service = SettingsService();
  AppSettings _settings = AppSettings.defaults();
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                '默认离线可用，日志和路径信息仅保存在本机',
                style: TextStyle(color: AppColors.muted, fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading)
            const AppCard(
              child: SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            _SettingsGrid(
              sections: [
                _generalSection(),
                _quarantineSection(),
                _performanceSection(),
                _privacySection(),
                _updateSection(),
              ],
            ),
          const SizedBox(height: 18),
          _ActionBar(
            saving: _saving,
            message: _message,
            onSave: _save,
            onReset: _reset,
          ),
        ],
      ),
    );
  }

  Widget _generalSection() {
    return _SettingsSection(
      icon: Icons.tune_outlined,
      asset: UiAssets.settingsGeneral,
      title: '常规',
      children: [
        _SwitchRow(
          title: '开机启动',
          subtitle: '当前版本先保存偏好，安装器接入后生效。',
          value: _settings.launchOnStartup,
          onChanged: (value) =>
              _update(_settings.copyWith(launchOnStartup: value)),
        ),
        _SwitchRow(
          title: '关闭时最小化到托盘',
          subtitle: '保留任务入口，避免误退出正在执行的任务。',
          value: _settings.minimizeToTray,
          onChanged: (value) =>
              _update(_settings.copyWith(minimizeToTray: value)),
        ),
        _ThemeModeRow(value: _settings.themeMode, onChanged: _updateThemeMode),
      ],
    );
  }

  Widget _quarantineSection() {
    return _SettingsSection(
      icon: Icons.security_outlined,
      asset: UiAssets.settingsQuarantine,
      title: '隔离与恢复',
      children: [
        _StepperRow(
          title: '隔离区保留天数',
          value: _settings.quarantineDays,
          min: 1,
          max: 30,
          onChanged: (value) =>
              _update(_settings.copyWith(quarantineDays: value)),
        ),
        _PathRow(
          title: '隔离根目录',
          subtitle: '留空则自动优先选择非 C 盘；空间不足时不会自动永久删除。',
          value: _settings.quarantinePath,
          onChanged: (value) =>
              _update(_settings.copyWith(quarantinePath: value.trim())),
        ),
      ],
    );
  }

  Widget _performanceSection() {
    return _SettingsSection(
      icon: Icons.speed_outlined,
      asset: UiAssets.settingsScan,
      title: '扫描与性能',
      children: [
        _DropdownRow(
          title: '扫描强度',
          value: _settings.scanMode,
          items: const {'light': '轻量', 'balanced': '均衡', 'deep': '深度'},
          onChanged: (value) => _update(_settings.copyWith(scanMode: value)),
        ),
        _SwitchRow(
          title: '跳过超大文件预览',
          subtitle: '扫描阶段仍统计大小，避免打开详情时卡顿。',
          value: _settings.skipLargeFiles,
          onChanged: (value) =>
              _update(_settings.copyWith(skipLargeFiles: value)),
        ),
        _SwitchRow(
          title: '游戏模式',
          subtitle: '降低扫描让步频率，减少前台应用卡顿。',
          value: _settings.gameMode,
          onChanged: (value) => _update(_settings.copyWith(gameMode: value)),
        ),
      ],
    );
  }

  Widget _privacySection() {
    return _SettingsSection(
      icon: Icons.privacy_tip_outlined,
      asset: UiAssets.privacyShield,
      title: '隐私与日志',
      children: [
        _SwitchRow(
          title: '隐藏敏感路径',
          subtitle: '详情和日志中优先显示脱敏路径。',
          value: _settings.hideSensitivePaths,
          onChanged: (value) =>
              _update(_settings.copyWith(hideSensitivePaths: value)),
        ),
        _SwitchRow(
          title: '日志仅本机保存',
          subtitle: 'V1 不上传文件名、路径、账号或消息内容。',
          value: _settings.localLogsOnly,
          onChanged: (value) =>
              _update(_settings.copyWith(localLogsOnly: value)),
        ),
      ],
    );
  }

  Widget _updateSection() {
    return _SettingsSection(
      icon: Icons.system_update_alt_outlined,
      title: '更新',
      children: [
        _DropdownRow(
          title: '更新通道',
          value: _settings.updateChannel,
          items: const {'stable': '稳定版', 'beta': '测试版'},
          onChanged: (value) =>
              _update(_settings.copyWith(updateChannel: value)),
        ),
        _SwitchRow(
          title: '自动检查规则更新',
          subtitle: '关闭后核心功能仍保持离线可用。',
          value: _settings.autoCheckRules,
          onChanged: (value) =>
              _update(_settings.copyWith(autoCheckRules: value)),
        ),
      ],
    );
  }

  Future<void> _load() async {
    final settings = await _service.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  void _update(AppSettings settings) {
    setState(() {
      _settings = settings;
      _message = '有未保存更改';
    });
  }

  Future<void> _updateThemeMode(String value) async {
    final next = _settings.copyWith(themeMode: value);
    setState(() {
      _settings = next;
      _message = value == 'dark' ? '已切换到黑夜主题' : '已切换到白天主题';
    });
    await AppThemeController.instance.setThemeMode(value);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _service.save(_settings);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = '设置已保存';
    });
  }

  void _reset() {
    setState(() {
      _settings = AppSettings.defaults();
      _message = '已恢复默认，保存后生效';
    });
    AppThemeController.instance.setThemeMode(_settings.themeMode);
  }
}

class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1020) {
          return Column(
            children: [
              for (final section in sections) ...[
                section,
                const SizedBox(height: 18),
              ],
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 1.9,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: sections,
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
    this.asset,
  });

  final IconData icon;
  final String? asset;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UiAssetIcon(
                asset: asset,
                fallback: icon,
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = value == 'dark';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text('切换白天 / 黑夜主题', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'light',
                icon: Icon(Icons.wb_sunny_outlined),
                label: Text('白天'),
              ),
              ButtonSegment(
                value: 'dark',
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('黑夜'),
              ),
            ],
            selected: {isDark ? 'dark' : 'light'},
            onSelectionChanged: (values) => onChanged(values.first),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 52,
          child: Text('$value 天', textAlign: TextAlign.center),
        ),
        IconButton(
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<String>(
            value: value,
            items: [
              for (final item in items.entries)
                DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: value,
            onChanged: onChanged,
            decoration: const InputDecoration(
              hintText: r'例如 D:\CDriveManagerQuarantine',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.saving,
    required this.message,
    required this.onSave,
    required this.onReset,
  });

  final bool saving;
  final String? message;
  final VoidCallback onSave;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? '设置仅保存在本机',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: saving ? null : onReset,
            child: const Text('恢复默认'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存设置'),
          ),
        ],
      ),
    );
  }
}
