import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/animated_app_dialog.dart';
import '../../widgets/app_card.dart';
import '../system_info/system_info_service.dart';
import 'app_migration_service.dart';

class AppMigrationPage extends StatefulWidget {
  const AppMigrationPage({super.key});

  @override
  State<AppMigrationPage> createState() => _AppMigrationPageState();
}

class _AppMigrationPageState extends State<AppMigrationPage> {
  final AppMigrationService _service = AppMigrationService();
  final Set<String> _selectedIds = <String>{};
  final Set<String> _expandedIds = <String>{};
  List<MigratableApp> _apps = const [];
  List<MigrationTargetVolume> _targets = const [];
  MigrationTargetVolume? _target;
  MigrationPlanResult? _lastPlan;
  MigrationExecutionResult? _lastExecution;
  bool _hasScanned = false;
  bool _scanning = false;
  bool _migrating = false;
  double _migrationProgress = 0;
  String? _migrationMessage;
  String? _error;

  int get _selectedBytes =>
      _selectedApps.fold(0, (sum, app) => sum + app.sizeBytes);

  List<MigratableApp> get _selectedApps =>
      _apps.where((app) => _selectedIds.contains(app.id)).toList();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1386),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(scanning: _scanning, hasScanned: _hasScanned, onScan: _scan),
          const SizedBox(height: 24),
          _SummaryCard(
            apps: _apps,
            selectedBytes: _selectedBytes,
            selectedCount: _selectedIds.length,
            targets: _targets,
            selectedTarget: _target,
            scanning: _scanning,
            onTargetChanged: (target) => setState(() => _target = target),
            onCreatePlan: _createPlan,
          ),
          const SizedBox(height: 22),
          if (_error != null) ...[
            _MessageCard(
              icon: Icons.error_outline,
              color: const Color(0xFFD93025),
              text: _error!,
            ),
            const SizedBox(height: 18),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 1040;
              final list = _ApplicationList(
                apps: _apps,
                selectedIds: _selectedIds,
                expandedIds: _expandedIds,
                scanning: _scanning,
                hasScanned: _hasScanned,
                onToggleApp: _toggleApp,
                onToggleAll: _toggleAllSelectableApps,
                onToggleExpand: _toggleExpand,
              );
              final safety = _MigrationSidePanel(
                target: _target,
                selectedApps: _selectedApps,
                lastPlan: _lastPlan,
                lastExecution: _lastExecution,
                migrating: _migrating,
                migrationProgress: _migrationProgress,
                migrationMessage: _migrationMessage,
                onExecutePlan: _executeMigration,
              );
              if (narrow) {
                return Column(
                  children: [list, const SizedBox(height: 18), safety],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: 20),
                  SizedBox(width: 430, child: safety),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    if (_migrating) return;
    setState(() {
      _scanning = true;
      _error = null;
      _lastPlan = null;
      _lastExecution = null;
    });
    try {
      final results = await Future.wait([
        _service.scanApps(),
        _service.scanTargetVolumes(),
      ]);
      final apps = results[0] as List<MigratableApp>;
      final targets = results[1] as List<MigrationTargetVolume>;
      if (!mounted) return;
      setState(() {
        _hasScanned = true;
        _apps = apps;
        _targets = targets;
        _target = targets
            .where((target) => target.usable)
            .cast<MigrationTargetVolume?>()
            .firstOrNull;
        _selectedIds
          ..clear()
          ..addAll(
            apps
                .where((app) => app.compatibility == AppCompatibility.movable)
                .map((app) => app.id),
          );
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _hasScanned = true;
          _error = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _toggleApp(MigratableApp app, bool selected) {
    if (!app.selectable || _scanning) return;
    setState(() {
      if (selected) {
        _selectedIds.add(app.id);
      } else {
        _selectedIds.remove(app.id);
      }
    });
  }

  void _toggleAllSelectableApps(bool selected) {
    if (_scanning) return;
    final selectableIds = _apps
        .where((app) => app.selectable)
        .map((app) => app.id);
    setState(() {
      if (selected) {
        _selectedIds.addAll(selectableIds);
      } else {
        _selectedIds.removeAll(selectableIds);
      }
    });
  }

  void _toggleExpand(String id) {
    setState(() {
      if (!_expandedIds.remove(id)) {
        _expandedIds.add(id);
      }
    });
  }

  Future<void> _createPlan() async {
    final target = _target;
    if (target == null || _selectedApps.isEmpty) return;
    final confirmed = await showAnimatedAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成应用迁移计划'),
        content: Text(
          '将为 ${_selectedApps.length} 个应用生成事务计划，目标盘为 ${target.drive}。\n\n'
          '当前步骤只写入可回滚迁移计划，不会静默移动目录；执行搬迁前仍需校验进程、空间、链接和备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('生成计划'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final plan = await _service.createPlan(apps: _selectedApps, target: target);
    if (!mounted) return;
    setState(() {
      _lastPlan = plan;
      _lastExecution = null;
    });
  }

  Future<void> _executeMigration() async {
    final planResult = _lastPlan;
    if (planResult == null || planResult.blockers.isNotEmpty || _migrating) {
      return;
    }
    final options = await showAnimatedAppDialog<MigrationRunOptions>(
      context: context,
      builder: (context) => _MigrationConfirmDialog(plan: planResult.plan),
    );
    if (options == null) return;
    setState(() {
      _migrating = true;
      _migrationProgress = 0;
      _migrationMessage = '准备迁移...';
      _lastExecution = null;
      _error = null;
    });
    final result = await _service.executePlan(
      planResult.plan,
      targetRootPath: options.targetRootPath,
      desktopShortcutAppIds: options.desktopShortcutAppIds,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _migrationProgress = progress.value;
          _migrationMessage = progress.message;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _lastExecution = result;
      _migrating = false;
      _migrationProgress = 1;
      _migrationMessage = result.hasFailure ? '迁移完成，部分失败' : '迁移完成';
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.scanning,
    required this.hasScanned,
    required this.onScan,
  });

  final bool scanning;
  final bool hasScanned;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('应用迁移', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '先扫描兼容性，再生成可回滚迁移计划',
                      style: TextStyle(color: AppColors.muted, fontSize: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: 176,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: scanning ? null : onScan,
            icon: scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.manage_search_outlined),
            label: Text(scanning ? '扫描中' : (hasScanned ? '重新扫描' : '开始扫描')),
          ),
        ),
      ],
    );
  }
}

class _MigrationConfirmDialog extends StatefulWidget {
  const _MigrationConfirmDialog({required this.plan});

  final MigrationPlan plan;

  @override
  State<_MigrationConfirmDialog> createState() =>
      _MigrationConfirmDialogState();
}

class _MigrationConfirmDialogState extends State<_MigrationConfirmDialog> {
  final Set<String> _shortcutIds = <String>{};
  final TextEditingController _customFolderController = TextEditingController(
    text: 'CDriveManager\\MigratedApps',
  );
  _TargetFolderMode _targetFolderMode = _TargetFolderMode.recommended;

  @override
  void dispose() {
    _customFolderController.dispose();
    super.dispose();
  }

  String get _recommendedPath =>
      '${widget.plan.targetDrive}\\CDriveManager\\MigratedApps';

  String get _rootPath => '${widget.plan.targetDrive}\\';

  String get _targetRootPath {
    return switch (_targetFolderMode) {
      _TargetFolderMode.root => _rootPath,
      _TargetFolderMode.recommended => _recommendedPath,
      _TargetFolderMode.custom => _normalizeDialogTargetPath(
        _customFolderController.text,
      ),
    };
  }

  String _normalizeDialogTargetPath(String value) {
    final raw = value.trim().replaceAll('/', '\\');
    if (raw.isEmpty) return _recommendedPath;
    if (raw.contains(':')) return raw;
    return '${widget.plan.targetDrive}\\$raw';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('开始迁移应用'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将迁移 ${widget.plan.apps.length} 个应用到 ${widget.plan.targetDrive}。'
              '\n执行会复制目录、校验文件、备份原目录并创建兼容链接。失败时会尝试自动回滚。',
            ),
            const SizedBox(height: 16),
            const Text('迁移位置', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<_TargetFolderMode>(
              segments: const [
                ButtonSegment(
                  value: _TargetFolderMode.recommended,
                  label: Text('推荐目录'),
                  icon: Icon(Icons.folder_special_outlined),
                ),
                ButtonSegment(
                  value: _TargetFolderMode.root,
                  label: Text('盘根目录'),
                  icon: Icon(Icons.drive_folder_upload_outlined),
                ),
                ButtonSegment(
                  value: _TargetFolderMode.custom,
                  label: Text('自定义'),
                  icon: Icon(Icons.create_new_folder_outlined),
                ),
              ],
              selected: {_targetFolderMode},
              onSelectionChanged: (value) {
                setState(() => _targetFolderMode = value.first);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customFolderController,
              enabled: _targetFolderMode == _TargetFolderMode.custom,
              decoration: InputDecoration(
                labelText: '目标文件夹',
                hintText: '可输入新文件夹名，或 ${widget.plan.targetDrive}\\Apps',
                helperText: '当前目标：$_targetRootPath',
              ),
            ),
            const SizedBox(height: 16),
            const Text('桌面快捷方式', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final app in widget.plan.apps)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _shortcutIds.contains(app.id),
                        activeColor: AppColors.primary,
                        title: Text(app.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          app.installPath,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _shortcutIds.add(app.id);
                            } else {
                              _shortcutIds.remove(app.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '未勾选的应用不会创建桌面快捷方式。迁移前请确认相关应用已经退出。',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            MigrationRunOptions(
              targetRootPath: _targetRootPath,
              desktopShortcutAppIds: Set<String>.from(_shortcutIds),
            ),
          ),
          child: const Text('开始迁移'),
        ),
      ],
    );
  }
}

enum _TargetFolderMode { recommended, root, custom }

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.apps,
    required this.selectedBytes,
    required this.selectedCount,
    required this.targets,
    required this.selectedTarget,
    required this.scanning,
    required this.onTargetChanged,
    required this.onCreatePlan,
  });

  final List<MigratableApp> apps;
  final int selectedBytes;
  final int selectedCount;
  final List<MigrationTargetVolume> targets;
  final MigrationTargetVolume? selectedTarget;
  final bool scanning;
  final ValueChanged<MigrationTargetVolume?> onTargetChanged;
  final VoidCallback onCreatePlan;

  @override
  Widget build(BuildContext context) {
    final movable = apps
        .where((app) => app.compatibility == AppCompatibility.movable)
        .length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 34,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Metric(label: '可迁移应用', value: '$movable / ${apps.length}'),
                _Metric(label: '已选择', value: '$selectedCount 个'),
                _Metric(label: '预计迁移', value: formatBytes(selectedBytes)),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<MigrationTargetVolume>(
                    initialValue: selectedTarget,
                    decoration: const InputDecoration(labelText: '目标盘'),
                    items: [
                      for (final target in targets)
                        DropdownMenuItem(
                          value: target,
                          enabled: target.usable,
                          child: Text(
                            '${target.drive} ${target.fileSystem} / 可用 ${formatBytes(target.freeBytes)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: scanning ? null : onTargetChanged,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 190,
            height: 56,
            child: FilledButton.icon(
              onPressed:
                  !scanning && selectedCount > 0 && selectedTarget != null
                  ? onCreatePlan
                  : null,
              icon: const Icon(Icons.playlist_add_check_outlined),
              label: const Text('生成计划'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ApplicationList extends StatelessWidget {
  const _ApplicationList({
    required this.apps,
    required this.selectedIds,
    required this.expandedIds,
    required this.scanning,
    required this.hasScanned,
    required this.onToggleApp,
    required this.onToggleAll,
    required this.onToggleExpand,
  });

  final List<MigratableApp> apps;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final bool scanning;
  final bool hasScanned;
  final void Function(MigratableApp app, bool selected) onToggleApp;
  final ValueChanged<bool> onToggleAll;
  final ValueChanged<String> onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final selectableCount = apps.where((app) => app.selectable).length;
    final selectedSelectableCount = apps
        .where((app) => app.selectable && selectedIds.contains(app.id))
        .length;
    final allSelected =
        selectableCount > 0 && selectedSelectableCount == selectableCount;
    final selectAllValue = selectedSelectableCount == 0
        ? false
        : allSelected
        ? true
        : null;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.drive_file_move_outline,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '可迁移应用',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              _SelectAllControl(
                value: selectAllValue,
                enabled: selectableCount > 0 && !scanning,
                selectedCount: selectedSelectableCount,
                totalCount: selectableCount,
                onChanged: (_) => onToggleAll(!allSelected),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _TableHeader(),
          if (apps.isEmpty)
            SizedBox(
              height: 250,
              child: Center(
                child: Text(
                  scanning
                      ? '正在扫描 C 盘非系统桌面应用...'
                      : (hasScanned
                            ? '未发现可迁移的 C 盘非系统应用'
                            : '点击“开始扫描”，查找 C 盘非系统应用'),
                ),
              ),
            )
          else
            for (final app in apps)
              _AppRow(
                app: app,
                selected: selectedIds.contains(app.id),
                expanded: expandedIds.contains(app.id),
                onToggleApp: onToggleApp,
                onToggleExpand: onToggleExpand,
              ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 54, right: 44, bottom: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('应用', style: _headerStyle)),
          Expanded(flex: 2, child: Text('安装位置', style: _headerStyle)),
          SizedBox(width: 86, child: Text('大小', style: _headerStyle)),
          SizedBox(width: 74, child: Text('位数', style: _headerStyle)),
          SizedBox(width: 86, child: Text('状态', style: _headerStyle)),
          SizedBox(width: 92, child: Text('兼容', style: _headerStyle)),
        ],
      ),
    );
  }
}

const _headerStyle = TextStyle(color: AppColors.muted, fontSize: 14);

class _SelectAllControl extends StatelessWidget {
  const _SelectAllControl({
    required this.value,
    required this.enabled,
    required this.selectedCount,
    required this.totalCount,
    required this.onChanged,
  });

  final bool? value;
  final bool enabled;
  final int selectedCount;
  final int totalCount;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE8ECEF)
        : AppColors.text;
    return InkWell(
      onTap: enabled ? () => onChanged(value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              tristate: true,
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: AppColors.primary,
            ),
            Text(
              value == true ? '取消全选' : '全选',
              style: TextStyle(
                color: enabled ? textColor : AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$selectedCount / $totalCount',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.expanded,
    required this.onToggleApp,
    required this.onToggleExpand,
  });

  final MigratableApp app;
  final bool selected;
  final bool expanded;
  final void Function(MigratableApp app, bool selected) onToggleApp;
  final ValueChanged<String> onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onToggleExpand(app.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Checkbox(
                      value: selected,
                      onChanged: app.selectable
                          ? (value) => onToggleApp(app, value ?? false)
                          : null,
                      activeColor: AppColors.primary,
                    ),
                  ),
                  Expanded(flex: 3, child: _AppName(app: app)),
                  Expanded(
                    flex: 2,
                    child: Tooltip(
                      message: app.installPath,
                      waitDuration: const Duration(milliseconds: 350),
                      child: Text(
                        app.installPath,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(width: 86, child: Text(formatBytes(app.sizeBytes))),
                  SizedBox(width: 74, child: Text(app.bitness)),
                  SizedBox(
                    width: 86,
                    child: Text(
                      app.running ? '运行中' : '未运行',
                      style: TextStyle(
                        color: app.running
                            ? const Color(0xFFE38400)
                            : AppColors.muted,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: _CompatibilityBadge(level: app.compatibility),
                  ),
                  SizedBox(
                    width: 44,
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _AppDetails(app: app),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class _AppName extends StatelessWidget {
  const _AppName({required this.app});

  final MigratableApp app;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: app.name,
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              app.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(height: 5),
          Tooltip(
            message: '${app.publisher} · ${app.version}',
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              '${app.publisher} · ${app.version}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDetails extends StatelessWidget {
  const _AppDetails({required this.app});

  final MigratableApp app;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final detailBackground = dark
        ? const Color(0xFF12181B)
        : const Color(0xFFF8FAFA);
    final fieldBackground = dark ? const Color(0xFF182024) : Colors.white;
    final textColor = dark ? const Color(0xFFE8ECEF) : AppColors.text;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(46, 0, 44, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: detailBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('应用名称', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: fieldBackground,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              app.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ).copyWith(color: textColor),
            ),
          ),
          const SizedBox(height: 14),
          const Text('安装路径', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: fieldBackground,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              app.installPath,
              style: TextStyle(color: textColor, height: 1.35),
            ),
          ),
          const SizedBox(height: 14),
          const Text('兼容判断', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final reason in app.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    _reasonIcon(app.compatibility),
                    size: 18,
                    color: _compatibilityColor(app.compatibility),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MigrationSidePanel extends StatelessWidget {
  const _MigrationSidePanel({
    required this.target,
    required this.selectedApps,
    required this.lastPlan,
    required this.lastExecution,
    required this.migrating,
    required this.migrationProgress,
    required this.migrationMessage,
    required this.onExecutePlan,
  });

  final MigrationTargetVolume? target;
  final List<MigratableApp> selectedApps;
  final MigrationPlanResult? lastPlan;
  final MigrationExecutionResult? lastExecution;
  final bool migrating;
  final double migrationProgress;
  final String? migrationMessage;
  final VoidCallback onExecutePlan;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('迁移安全说明', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 22),
          const _SafetyPoint(
            title: '目标盘校验',
            body: '目标必须是非 C 盘、本地固定 NTFS 卷，并预留校验空间。',
          ),
          const _SafetyPoint(
            title: '运行进程保护',
            body: '运行中的应用不会静默中断，执行迁移前需要用户确认退出。',
          ),
          const _SafetyPoint(
            title: '事务日志',
            body: '计划写入本机事务文件，后续 native 搬迁按该顺序复制、校验、建链接和回滚。',
          ),
          const Divider(height: 30),
          Text(
            '已选 ${selectedApps.length} 个 / ${formatBytes(selectedApps.fold(0, (sum, app) => sum + app.sizeBytes))}',
          ),
          const SizedBox(height: 10),
          Text(
            target == null
                ? '未选择目标盘'
                : '目标盘 ${target!.drive}，可用 ${formatBytes(target!.freeBytes)}',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (lastPlan != null) ...[
            const SizedBox(height: 16),
            _PlanResultCard(
              result: lastPlan!,
              execution: lastExecution,
              migrating: migrating,
              migrationProgress: migrationProgress,
              migrationMessage: migrationMessage,
              onExecutePlan: onExecutePlan,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanResultCard extends StatelessWidget {
  const _PlanResultCard({
    required this.result,
    required this.execution,
    required this.migrating,
    required this.migrationProgress,
    required this.migrationMessage,
    required this.onExecutePlan,
  });

  final MigrationPlanResult result;
  final MigrationExecutionResult? execution;
  final bool migrating;
  final double migrationProgress;
  final String? migrationMessage;
  final VoidCallback onExecutePlan;

  @override
  Widget build(BuildContext context) {
    final blocked = result.blockers.isNotEmpty;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE8ECEF)
        : AppColors.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: blocked ? const Color(0xFFFFF2F2) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            blocked ? '计划已阻止' : '计划已生成',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: blocked ? const Color(0xFFD93025) : AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.plan.transactionPath,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          for (final item in [...result.blockers, ...result.warnings]) ...[
            const SizedBox(height: 8),
            Text('· $item', style: TextStyle(fontSize: 13, color: textColor)),
          ],
          if (!blocked) ...[
            const SizedBox(height: 12),
            if (migrating) ...[
              LinearProgressIndicator(
                value: migrationProgress.clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                migrationMessage ?? '正在迁移...',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onExecutePlan,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('开始迁移'),
                ),
              ),
          ],
          if (execution != null) ...[
            const SizedBox(height: 12),
            Text(
              '成功 ${execution!.migrated.length} 个，失败 ${execution!.failed.length} 个',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: execution!.hasFailure
                    ? const Color(0xFFD93025)
                    : AppColors.primary,
              ),
            ),
            for (final item in execution!.messages.take(4)) ...[
              const SizedBox(height: 6),
              Text(
                item,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SafetyPoint extends StatelessWidget {
  const _SafetyPoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.security_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CompatibilityBadge extends StatelessWidget {
  const _CompatibilityBadge({required this.level});

  final AppCompatibility level;

  @override
  Widget build(BuildContext context) {
    final color = _compatibilityColor(level);
    final label = switch (level) {
      AppCompatibility.movable => '可迁移',
      AppCompatibility.caution => '谨慎',
      AppCompatibility.unsupported => '不支持',
    };
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

Color _compatibilityColor(AppCompatibility level) {
  return switch (level) {
    AppCompatibility.movable => AppColors.primary,
    AppCompatibility.caution => const Color(0xFFE38400),
    AppCompatibility.unsupported => const Color(0xFFD93025),
  };
}

IconData _reasonIcon(AppCompatibility level) {
  return switch (level) {
    AppCompatibility.movable => Icons.check_circle_outline,
    AppCompatibility.caution => Icons.warning_amber_rounded,
    AppCompatibility.unsupported => Icons.block,
  };
}
