import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/animated_app_dialog.dart';
import '../../widgets/app_card.dart';
import '../settings/settings_service.dart';
import 'quarantine_service.dart';

/// 隔离区页面：列表、恢复、清空到期项、打开隔离文件夹。
class QuarantinePage extends StatefulWidget {
  const QuarantinePage({super.key});

  @override
  State<QuarantinePage> createState() => _QuarantinePageState();
}

class _QuarantinePageState extends State<QuarantinePage> {
  final SettingsService _settingsService = SettingsService();
  QuarantineService _service = QuarantineService();
  final Set<String> _selectedIds = <String>{};

  List<QuarantineItem> _items = const [];
  String _rootPath = '';
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalBytes = _items.fold<int>(0, (sum, item) => sum + item.bytes);
    final expiredCount =
        _items
            .where((item) => item.statusAt(now) == QuarantineStatus.expired)
            .length;
    final selected =
        _items.where((item) => _selectedIds.contains(item.id)).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1386),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('隔离区', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  '可恢复项目保留在非 C 盘隔离区，到期前可恢复到原路径',
                  style: TextStyle(color: AppColors.muted, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SummaryCard(
            loading: _loading,
            totalBytes: totalBytes,
            itemCount: _items.length,
            expiredCount: expiredCount,
            rootPath: _rootPath,
            busy: _busy,
            onRefresh: _reload,
            onOpenFolder: _openFolder,
            onPurgeExpired: expiredCount > 0 ? _purgeExpired : null,
            onRestoreSelected: selected.isNotEmpty ? _restoreSelected : null,
            onPurgeSelected: selected.isNotEmpty ? _purgeSelected : null,
          ),
          const SizedBox(height: 22),
          if (_message != null) ...[
            Text(
              _message!,
              style: const TextStyle(color: AppColors.primary, fontSize: 15),
            ),
            const SizedBox(height: 12),
          ],
          _ItemListCard(
            loading: _loading,
            items: _items,
            selectedIds: _selectedIds,
            now: now,
            onToggle: _toggleItem,
            onToggleAll: _toggleAll,
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final settings = await _settingsService.load();
    _service = QuarantineService(
      defaultRetentionDays: settings.quarantineDays,
      configuredRoot: settings.quarantinePath,
    );
    final root = await _service.resolveRoot();
    final items = await _service.listItems();
    if (!mounted) return;
    setState(() {
      _rootPath = root.path;
      _items = items;
      _selectedIds.removeWhere((id) => items.every((item) => item.id != id));
      _loading = false;
    });
  }

  void _toggleItem(QuarantineItem item) {
    setState(() {
      if (!_selectedIds.remove(item.id)) {
        _selectedIds.add(item.id);
      }
    });
  }

  void _toggleAll(bool selected) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(selected ? _items.map((item) => item.id) : const <String>[]);
    });
  }

  Future<void> _openFolder() async {
    await _service.openQuarantineFolder();
  }

  Future<void> _restoreSelected() async {
    final selected =
        _items.where((item) => _selectedIds.contains(item.id)).toList();
    if (selected.isEmpty || _busy) return;

    final confirmed = await showAnimatedAppDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认恢复'),
            content: Text(
              '将把 ${selected.length} 个文件恢复到原路径。'
              '若原路径已存在同名文件，将跳过以避免覆盖。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('开始恢复'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await _service.restoreItems(selected);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message =
          '已恢复 ${result.successCount} 项（${formatQuarantineBytes(result.bytes)}）'
          '${result.failedCount > 0 ? '，失败 ${result.failedCount} 项' : ''}';
    });
    await _reload();
  }

  Future<void> _purgeSelected() async {
    final selected =
        _items.where((item) => _selectedIds.contains(item.id)).toList();
    if (selected.isEmpty || _busy) return;

    final confirmed = await showAnimatedAppDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认永久删除'),
            content: Text(
              '将永久删除选中的 ${selected.length} 个隔离项，'
              '共 ${formatQuarantineBytes(selected.fold<int>(0, (s, i) => s + i.bytes))}。'
              '\n此操作不可恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('永久删除'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await _service.purgeItems(selected);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message =
          '已清空 ${result.successCount} 项（${formatQuarantineBytes(result.bytes)}）';
    });
    await _reload();
  }

  Future<void> _purgeExpired() async {
    if (_busy) return;
    final confirmed = await showAnimatedAppDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清空到期项'),
            content: const Text(
              '仅永久删除已到期且索引完整的隔离文件，未到期项目会保留。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('清空到期'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await _service.purgeExpired();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message =
          '已清理到期 ${result.successCount} 项（${formatQuarantineBytes(result.bytes)}）';
    });
    await _reload();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.loading,
    required this.totalBytes,
    required this.itemCount,
    required this.expiredCount,
    required this.rootPath,
    required this.busy,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onPurgeExpired,
    required this.onRestoreSelected,
    required this.onPurgeSelected,
  });

  final bool loading;
  final int totalBytes;
  final int itemCount;
  final int expiredCount;
  final String rootPath;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;
  final VoidCallback? onPurgeExpired;
  final VoidCallback? onRestoreSelected;
  final VoidCallback? onPurgeSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '隔离占用',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loading ? '--' : formatQuarantineBytes(totalBytes),
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loading
                          ? '正在读取隔离索引...'
                          : '共 $itemCount 项，其中到期 $expiredCount 项',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                      ),
                    ),
                    if (rootPath.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '位置：$rootPath',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onOpenFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('打开目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onPurgeExpired,
                    icon: const Icon(Icons.hourglass_disabled_outlined),
                    label: const Text('清空到期'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : onRestoreSelected,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('恢复所选'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onPurgeSelected,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('永久删除'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemListCard extends StatelessWidget {
  const _ItemListCard({
    required this.loading,
    required this.items,
    required this.selectedIds,
    required this.now,
    required this.onToggle,
    required this.onToggleAll,
  });

  final bool loading;
  final List<QuarantineItem> items;
  final Set<String> selectedIds;
  final DateTime now;
  final ValueChanged<QuarantineItem> onToggle;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final allSelected =
        items.isNotEmpty && items.every((item) => selectedIds.contains(item.id));

    return AppCard(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('隔离记录', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => onToggleAll(!allSelected),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (loading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48),
              decoration: BoxDecoration(
                color: AppColors.primarySoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 36, color: AppColors.muted),
                  SizedBox(height: 12),
                  Text(
                    '暂无隔离记录',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '微信专清等高风险清理会先把可恢复文件移入这里',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            )
          else ...[
            const _HeaderRow(),
            for (final item in items)
              _ItemRow(
                item: item,
                selected: selectedIds.contains(item.id),
                status: item.statusAt(now),
                onToggle: () => onToggle(item),
              ),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 48),
          Expanded(flex: 3, child: Text('文件', style: _headerStyle)),
          Expanded(flex: 2, child: Text('来源', style: _headerStyle)),
          Expanded(child: Text('大小', style: _headerStyle)),
          Expanded(child: Text('状态', style: _headerStyle)),
          Expanded(flex: 2, child: Text('到期时间', style: _headerStyle)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.selected,
    required this.status,
    required this.onToggle,
  });

  final QuarantineItem item;
  final bool selected;
  final QuarantineStatus status;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Checkbox(value: selected, onChanged: (_) => onToggle()),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.originalPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('${item.source} / ${item.category}'),
            ),
            Expanded(child: Text(formatQuarantineBytes(item.bytes))),
            Expanded(child: _StatusChip(status: status)),
            Expanded(
              flex: 2,
              child: Text(_formatDate(item.expireAt)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final QuarantineStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      QuarantineStatus.retained => AppColors.primary,
      QuarantineStatus.expiring => const Color(0xFFC9852A),
      QuarantineStatus.expired => const Color(0xFFC4554D),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        quarantineStatusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

const _headerStyle = TextStyle(
  color: AppColors.muted,
  fontWeight: FontWeight.w700,
  fontSize: 13,
);
