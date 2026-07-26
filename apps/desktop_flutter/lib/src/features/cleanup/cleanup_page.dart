import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'cleanup_service.dart';

class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key});

  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage> {
  final CleanupService _service = CleanupService();
  final Set<String> _selectedKeys = <String>{};
  final Set<String> _expandedIds = <String>{};
  List<CleanupCategoryResult> _results = const [];
  bool _scanning = false;
  bool _cleaning = false;
  bool _cancelRequested = false;
  double _scanProgress = 0;
  double _cleanProgress = 0;
  int _cleanedBytes = 0;
  String? _activeRuleId;
  CleanupExecutionResult? _lastClean;

  Iterable<CleanupFileItem> get _selectedFiles => _results
      .expand(
        (category) => category.files.where(
          (file) => _selectedKeys.contains(_selectionKey(category.rule.id, file)),
        ),
      );

  int get _totalBytes => _results.fold(0, (sum, item) => sum + item.bytes);

  int get _selectedBytes => _dedupeFilesByPath(
    _selectedFiles,
  ).fold(0, (sum, item) => sum + item.bytes);

  int get _selectedCount => _selectedKeys.length;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1386),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(),
              const SizedBox(height: 30),
              DiskSummary(
                scanning: _scanning,
                cleaning: _cleaning,
                scanned: _results.isNotEmpty,
                totalBytes: _totalBytes,
                selectedBytes: _selectedBytes,
                scanProgress: _scanProgress,
                onScan: _startScan,
                onCancel: _requestCancel,
                onClean: _confirmAndClean,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 1040;
                  final table = CleanupRecommendationCard(
                    items: _results,
                    selectedKeys: _selectedKeys,
                    expandedIds: _expandedIds,
                    scanning: _scanning,
                    activeRuleId: _activeRuleId,
                    onToggleCategory: _toggleCategory,
                    onToggleFile: _toggleFile,
                    onToggleExpand: _toggleExpand,
                  );
                  final safety = CleanupSidePanel(
                    selectedBytes: _selectedBytes,
                    selectedFiles: _selectedCount,
                    lastClean: _lastClean,
                  );
                  if (narrow) {
                    return Column(
                      children: [
                        table,
                        const SizedBox(height: 18),
                        safety,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: table),
                      const SizedBox(width: 20),
                      SizedBox(width: 430, child: safety),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              RecentTaskStrip(lastClean: _lastClean),
            ],
          ),
          if (_cleaning)
            CleaningOverlay(
              progress: _cleanProgress,
              cleanedBytes: _cleanedBytes,
            ),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _cleaning = false;
      _cancelRequested = false;
      _activeRuleId = null;
      _lastClean = null;
      _scanProgress = 0;
    });

    final results = await _service.scan(
      shouldCancel: () => _cancelRequested,
      onRuleStarted: (ruleId) {
        if (mounted) setState(() => _activeRuleId = ruleId);
      },
      onProgress: (progress) {
        if (mounted) {
          setState(() => _scanProgress = progress.clamp(0.0, 1.0).toDouble());
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _results = results;
      _selectedKeys
        ..clear()
        ..addAll(
          results
              .where((item) => item.rule.defaultSelected)
              .expand(
                (item) => item.files.map(
                  (file) => _selectionKey(item.rule.id, file),
                ),
              ),
        );
      _scanning = false;
      _activeRuleId = null;
      _scanProgress = 1;
    });
  }

  void _requestCancel() {
    setState(() => _cancelRequested = true);
  }

  void _toggleCategory(CleanupCategoryResult category, bool selected) {
    if (_scanning || _cleaning) return;
    setState(() {
      final keys = category.files.map(
        (file) => _selectionKey(category.rule.id, file),
      );
      if (selected) {
        _selectedKeys.addAll(keys);
      } else {
        _selectedKeys.removeAll(keys);
      }
    });
  }

  void _toggleFile(CleanupCategoryResult category, CleanupFileItem file) {
    if (_scanning || _cleaning) return;
    final key = _selectionKey(category.rule.id, file);
    setState(() {
      if (!_selectedKeys.remove(key)) {
        _selectedKeys.add(key);
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

  Future<void> _confirmAndClean() async {
    final selected = _dedupeFilesByPath(_selectedFiles);
    if (selected.isEmpty || _cleaning || _scanning) return;

    final selectedCategoryIds = _results
        .where(
          (category) => category.files.any(
            (file) =>
                _selectedKeys.contains(_selectionKey(category.rule.id, file)),
          ),
        )
        .map((category) => category.rule.id)
        .toSet();
    final hasCaution = _results.any(
      (category) =>
          selectedCategoryIds.contains(category.rule.id) &&
          category.rule.risk != CleanupRisk.safe,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasCaution ? '确认清理谨慎项目' : '确认开始清理'),
        content: Text(
          '将清理 ${formatBytes(_selectedBytes)}，共 $_selectedCount 个文件。'
          '${hasCaution ? '\n\n已选择回收站等谨慎项目，清理后当前版本暂不提供恢复。' : '\n\n锁定或权限不足的文件会自动跳过。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cleaning = true;
      _cancelRequested = false;
      _lastClean = null;
      _cleanProgress = 0;
      _cleanedBytes = 0;
    });

    final result = await _service.cleanFiles(
      selected,
      shouldCancel: () => _cancelRequested,
      onProgress: (progress, deletedBytes) {
        if (!mounted) return;
        setState(() {
          _cleanProgress = progress.clamp(0.0, 1.0).toDouble();
          _cleanedBytes = deletedBytes;
        });
      },
    );
    _cancelRequested = false;
    final refreshed = await _service.scan();

    if (!mounted) return;
    setState(() {
      _lastClean = result;
      _results = refreshed;
      _selectedKeys
        ..clear()
        ..addAll(
          refreshed
              .where((item) => item.rule.defaultSelected)
              .expand(
                (item) => item.files.map(
                  (file) => _selectionKey(item.rule.id, file),
                ),
              ),
        );
      _expandedIds.clear();
      _cleaning = false;
      _cleanProgress = 1;
    });
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'C 盘空间一目了然',
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontSize: 40, letterSpacing: 0),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '扫描与清理均在本机完成，高风险项目默认不选中',
                style: TextStyle(color: AppColors.muted, fontSize: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class DiskSummary extends StatelessWidget {
  const DiskSummary({
    super.key,
    required this.scanning,
    required this.cleaning,
    required this.scanned,
    required this.totalBytes,
    required this.selectedBytes,
    required this.scanProgress,
    required this.onScan,
    required this.onCancel,
    required this.onClean,
  });

  final bool scanning;
  final bool cleaning;
  final bool scanned;
  final int totalBytes;
  final int selectedBytes;
  final double scanProgress;
  final VoidCallback onScan;
  final VoidCallback onCancel;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final busy = scanning || cleaning;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('可释放空间', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  scanned ? formatBytes(totalBytes) : '--',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 16),
                ScanProgressStrip(
                  busy: busy,
                  progress: scanProgress,
                  selectedBytes: selectedBytes,
                  totalBytes: totalBytes,
                ),
                const SizedBox(height: 12),
                Text(
                  busy
                      ? (scanning ? '正在扫描明确规则命中的目录...' : '正在清理，锁定文件会跳过...')
                      : '已选择 ${formatBytes(selectedBytes)}，低风险项默认勾选',
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          SizedBox(
            width: 190,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: busy ? onCancel : onScan,
              icon: Icon(busy ? Icons.stop_rounded : Icons.refresh_rounded),
              label: Text(busy ? '取消' : (scanned ? '重新扫描' : '开始扫描')),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 190,
            height: 56,
            child: FilledButton.icon(
              onPressed: scanned && !busy && selectedBytes > 0 ? onClean : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('清理所选'),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanProgressStrip extends StatelessWidget {
  const ScanProgressStrip({
    super.key,
    required this.busy,
    required this.progress,
    required this.selectedBytes,
    required this.totalBytes,
  });

  final bool busy;
  final double progress;
  final int selectedBytes;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.border),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: busy
                  ? progress.clamp(0.02, 1.0).toDouble()
                  : (totalBytes == 0 ? 0 : selectedBytes / totalBytes),
              child: const ColoredBox(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class CleaningOverlay extends StatelessWidget {
  const CleaningOverlay({
    super.key,
    required this.progress,
    required this.cleanedBytes,
  });

  final double progress;
  final int cleanedBytes;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();
    return Positioned(
      top: 18,
      right: 18,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(238),
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress.clamp(0.02, 1.0).toDouble(),
                          strokeWidth: 5,
                          backgroundColor: AppColors.border,
                          color: AppColors.primary,
                        ),
                        Center(
                          child: Text(
                            '$percent%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '正在清理垃圾',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '已释放 ${formatBytes(cleanedBytes)}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.02, 1.0).toDouble(),
                            minHeight: 8,
                            backgroundColor: AppColors.border,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CleanupRecommendationCard extends StatelessWidget {
  const CleanupRecommendationCard({
    super.key,
    required this.items,
    required this.selectedKeys,
    required this.expandedIds,
    required this.scanning,
    required this.activeRuleId,
    required this.onToggleCategory,
    required this.onToggleFile,
    required this.onToggleExpand,
  });

  final List<CleanupCategoryResult> items;
  final Set<String> selectedKeys;
  final Set<String> expandedIds;
  final bool scanning;
  final String? activeRuleId;
  final void Function(CleanupCategoryResult category, bool selected)
  onToggleCategory;
  final void Function(CleanupCategoryResult category, CleanupFileItem file)
  onToggleFile;
  final ValueChanged<String> onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('清理计划', style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            EmptyCleanupState(scanning: scanning)
          else ...[
            const CleanupTableHeader(),
            for (final item in items)
              CleanupCategoryTile(
                key: ValueKey('cleanup-category-${item.rule.id}'),
                item: item,
                selectedKeys: selectedKeys,
                expanded: expandedIds.contains(item.rule.id),
                active: activeRuleId == item.rule.id,
                onToggleCategory: onToggleCategory,
                onToggleFile: onToggleFile,
                onToggleExpand: onToggleExpand,
              ),
          ],
        ],
      ),
    );
  }
}

class EmptyCleanupState extends StatelessWidget {
  const EmptyCleanupState({super.key, required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            scanning ? Icons.manage_search : Icons.cleaning_services_outlined,
            color: AppColors.primary,
            size: 54,
          ),
          const SizedBox(height: 16),
          Text(
            scanning ? '正在生成可解释清理计划' : '点击开始扫描，查找可安全清理的垃圾文件',
            style: const TextStyle(fontSize: 17, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

class CleanupTableHeader extends StatelessWidget {
  const CleanupTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 56, right: 4, bottom: 10),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('项目', style: _headerStyle)),
          Expanded(flex: 2, child: Text('来源', style: _headerStyle)),
          Expanded(child: Text('大小', style: _headerStyle)),
          Expanded(child: Text('文件数', style: _headerStyle)),
          Expanded(child: Text('可恢复', style: _headerStyle)),
          SizedBox(width: 86),
          SizedBox(width: 44),
        ],
      ),
    );
  }
}

const _headerStyle = TextStyle(color: AppColors.muted, fontSize: 14);

class CleanupCategoryTile extends StatelessWidget {
  const CleanupCategoryTile({
    super.key,
    required this.item,
    required this.selectedKeys,
    required this.expanded,
    required this.active,
    required this.onToggleCategory,
    required this.onToggleFile,
    required this.onToggleExpand,
  });

  final CleanupCategoryResult item;
  final Set<String> selectedKeys;
  final bool expanded;
  final bool active;
  final void Function(CleanupCategoryResult category, bool selected)
  onToggleCategory;
  final void Function(CleanupCategoryResult category, CleanupFileItem file)
  onToggleFile;
  final ValueChanged<String> onToggleExpand;

  int get _selectedCount =>
      item.files
          .where(
            (file) => selectedKeys.contains(_selectionKey(item.rule.id, file)),
          )
          .length;

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedCount;
    final checkboxValue = selectedCount == 0
        ? false
        : selectedCount == item.files.length
        ? true
        : null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: item.hasFiles ? () => onToggleExpand(item.rule.id) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Checkbox(
                      key: ValueKey('category-checkbox-${item.rule.id}'),
                      tristate: true,
                      value: checkboxValue,
                      // Mixed means "partially selected"; clicking the parent
                      // should clear it instead of selecting the remaining rows.
                      onChanged: item.hasFiles
                          ? (_) => onToggleCategory(item, selectedCount == 0)
                          : null,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Icon(
                      _iconFor(item.rule.id),
                      color: _riskColor(item.rule.risk),
                      size: 32,
                    ),
                  ),
                  Expanded(flex: 4, child: _CategoryName(item: item, active: active)),
                  Expanded(
                    flex: 2,
                    child: Text(item.rule.source, style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: Text(formatBytes(item.bytes), style: _cellStyle),
                  ),
                  Expanded(child: Text('${item.fileCount}', style: _cellStyle)),
                  Expanded(
                    child: Text(
                      item.rule.recoverable ? '是' : '否',
                      style: const TextStyle(fontSize: 15, color: AppColors.muted),
                    ),
                  ),
                  SizedBox(width: 86, child: RiskBadge(level: item.rule.risk)),
                  SizedBox(
                    width: 44,
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: item.hasFiles ? AppColors.muted : AppColors.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: CleanupFileList(
              key: ValueKey('cleanup-files-${item.rule.id}'),
              category: item,
              files: item.files,
              selectedKeys: selectedKeys,
              onToggleFile: onToggleFile,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

const _cellStyle = TextStyle(fontSize: 15, color: AppColors.text);

class _CategoryName extends StatelessWidget {
  const _CategoryName({required this.item, required this.active});

  final CleanupCategoryResult item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  item.rule.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            item.rule.subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          if (item.skipped > 0) ...[
            const SizedBox(height: 6),
            Text(
              '已跳过 ${item.skipped} 个无权限、锁定或链接项目',
              style: const TextStyle(fontSize: 12, color: Color(0xFFE38400)),
            ),
          ],
        ],
      ),
    );
  }
}

class CleanupFileList extends StatefulWidget {
  const CleanupFileList({
    super.key,
    required this.category,
    required this.files,
    required this.selectedKeys,
    required this.onToggleFile,
  });

  final CleanupCategoryResult category;
  final List<CleanupFileItem> files;
  final Set<String> selectedKeys;
  final void Function(CleanupCategoryResult category, CleanupFileItem file)
  onToggleFile;

  @override
  State<CleanupFileList> createState() => _CleanupFileListState();
}

class _CleanupFileListState extends State<CleanupFileList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return const SizedBox.shrink();
    }
    final height = _detailHeight(widget.files.length);
    return Container(
      margin: const EdgeInsets.fromLTRB(94, 0, 44, 16),
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFA),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        interactive: true,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.only(right: 12),
          physics: const AlwaysScrollableScrollPhysics(),
          primary: false,
          itemExtent: _detailRowHeight,
          cacheExtent: _detailRowHeight * 6,
          itemCount: widget.files.length,
          itemBuilder: (context, index) {
            final file = widget.files[index];
            final key = _selectionKey(widget.category.rule.id, file);
            final selected = widget.selectedKeys.contains(key);
            return DecoratedBox(
              key: ValueKey('cleanup-file-$key'),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: InkWell(
                onTap: () => widget.onToggleFile(widget.category, file),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (_) =>
                            widget.onToggleFile(widget.category, file),
                        activeColor: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name.isEmpty ? '(无文件名)' : file.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              file.path,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 92,
                        child: Text(
                          '${formatBytes(file.bytes)}\n${_formatDate(file.modified)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Keep the detail list bounded so ListView can virtualize large scan results.
  double _detailHeight(int itemCount) {
    const maxHeight = 280.0;
    final desired = itemCount * _detailRowHeight;
    if (desired < _detailRowHeight) return _detailRowHeight;
    return desired > maxHeight ? maxHeight : desired;
  }
}

const _detailRowHeight = 72.0;

class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level});

  final CleanupRisk level;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(level);
    final label = switch (level) {
      CleanupRisk.safe => '安全',
      CleanupRisk.caution => '谨慎',
      CleanupRisk.high => '高风险',
    };
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

class CleanupSidePanel extends StatelessWidget {
  const CleanupSidePanel({
    super.key,
    required this.selectedBytes,
    required this.selectedFiles,
    required this.lastClean,
  });

  final int selectedBytes;
  final int selectedFiles;
  final CleanupExecutionResult? lastClean;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('安全说明', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 22),
          const SafetyPoint(title: '先扫描，再确认', body: '每一类都会展示来源、大小、文件数和风险级别。'),
          const SafetyPoint(title: '高风险默认不选', body: '回收站等可能包含用户资料的项目需要手动勾选。'),
          const SafetyPoint(title: '文件级选择', body: '展开分类后可以单独勾选垃圾项，再执行清理。'),
          const Divider(height: 30),
          Text('已选 ${formatBytes(selectedBytes)} / $selectedFiles 个文件'),
          if (lastClean != null) ...[
            const SizedBox(height: 14),
            Text(
              '上次释放 ${formatBytes(lastClean!.deletedBytes)}，'
              '成功 ${lastClean!.deletedFiles}，失败 ${lastClean!.failedFiles}，'
              '跳过 ${lastClean!.skippedFiles}',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class SafetyPoint extends StatelessWidget {
  const SafetyPoint({super.key, required this.title, required this.body});

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
            child: const Icon(Icons.verified_user_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
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

class RecentTaskStrip extends StatelessWidget {
  const RecentTaskStrip({super.key, required this.lastClean});

  final CleanupExecutionResult? lastClean;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: InkWell(
        onTap: () => _showRecentTaskDialog(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.history, color: AppColors.muted, size: 24),
              const SizedBox(width: 14),
              const Text(
                '最近任务',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 28),
              Icon(
                lastClean == null ? Icons.info_outline : Icons.check_circle,
                color: lastClean == null ? AppColors.muted : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lastClean == null
                      ? '暂无清理记录'
                      : '本次清理完成，释放 ${formatBytes(lastClean!.deletedBytes)}',
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
              const Text(
                '查看详情',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecentTaskDialog(BuildContext context) {
    final result = lastClean;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最近任务'),
        content: result == null
            ? const Text('暂无清理记录。完成一次清理后，这里会展示释放空间、成功、失败和跳过数量。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TaskMetric(label: '释放空间', value: formatBytes(result.deletedBytes)),
                  _TaskMetric(label: '成功清理', value: '${result.deletedFiles} 个文件'),
                  _TaskMetric(label: '失败', value: '${result.failedFiles} 个文件'),
                  _TaskMetric(label: '跳过', value: '${result.skippedFiles} 个文件'),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _TaskMetric extends StatelessWidget {
  const _TaskMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(String id) {
  return switch (id) {
    'system_temp' => Icons.folder_copy_outlined,
    'app_cache' => Icons.layers_outlined,
    'logs_dumps' => Icons.bug_report_outlined,
    'recycle_bin' => Icons.delete_outline,
    _ => Icons.cleaning_services_outlined,
  };
}

Color _riskColor(CleanupRisk risk) {
  return switch (risk) {
    CleanupRisk.safe => AppColors.primary,
    CleanupRisk.caution => const Color(0xFFE38400),
    CleanupRisk.high => const Color(0xFFD93025),
  };
}

// The same file can be matched by more than one rule, so UI selection must be
// scoped to the category while the final delete plan remains path-deduplicated.
String _selectionKey(String categoryId, CleanupFileItem file) {
  return '$categoryId\u0000${file.path.toLowerCase()}';
}

List<CleanupFileItem> _dedupeFilesByPath(Iterable<CleanupFileItem> files) {
  final seen = <String>{};
  final deduped = <CleanupFileItem>[];
  for (final file in files) {
    final normalized = file.path.toLowerCase();
    if (seen.add(normalized)) {
      deduped.add(file);
    }
  }
  return deduped;
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
}
