import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/ui_assets.dart';
import '../../widgets/animated_app_dialog.dart';
import '../../widgets/app_card.dart';
import '../../widgets/risk_pill.dart';
import '../../widgets/task_progress_overlay.dart';
import '../../widgets/task_result_dialog.dart';
import '../settings/settings_service.dart';
import 'wechat_service.dart';

/// 微信专清页面：账号识别、分类扫描、高风险二次确认、隔离优先清理。
class WechatPage extends StatefulWidget {
  const WechatPage({super.key});

  @override
  State<WechatPage> createState() => _WechatPageState();
}

class _WechatPageState extends State<WechatPage> {
  final WechatService _service = WechatService();
  final SettingsService _settingsService = SettingsService();
  final Set<String> _selectedKeys = <String>{};
  final Set<String> _expandedIds = <String>{};
  final TextEditingController _customPathController = TextEditingController();

  List<WechatAccount> _accounts = const [];
  WechatAccount? _selectedAccount;
  List<WechatCategoryResult> _results = const [];
  bool _loadingAccounts = true;
  bool _scanning = false;
  bool _cleaning = false;
  bool _wechatRunning = false;
  bool _cancelRequested = false;
  bool _ackHighRisk = false;
  double _scanProgress = 0;
  double _cleanProgress = 0;
  int _cleanedBytes = 0;
  String? _activeRuleId;
  WechatCleanResult? _lastClean;
  String? _message;

  Iterable<WechatFileItem> get _selectedFiles => _results.expand(
    (category) => category.files.where(
      (file) =>
          _selectedKeys.contains(WechatService.selectionKey(category.rule.id, file)),
    ),
  );

  int get _totalBytes => _results.fold(0, (sum, item) => sum + item.bytes);

  int get _selectedBytes => _selectedFiles.fold(0, (sum, item) => sum + item.bytes);

  bool get _hasHighRiskSelected => _results.any(
    (category) =>
        category.rule.risk != WechatRisk.safe &&
        category.files.any(
          (file) => _selectedKeys.contains(
            WechatService.selectionKey(category.rule.id, file),
          ),
        ),
  );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1386),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('微信专清', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '按账号和类型管理微信占用，扫描仅在本机完成，不展示消息正文',
                      style: TextStyle(color: AppColors.muted, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _AccountBar(
                loading: _loadingAccounts,
                accounts: _accounts,
                selected: _selectedAccount,
                wechatRunning: _wechatRunning,
                customController: _customPathController,
                onRefresh: _bootstrap,
                onSelect: _selectAccount,
                onAddCustom: _addCustomAccount,
              ),
              const SizedBox(height: 20),
              _SummaryCard(
                scanning: _scanning,
                cleaning: _cleaning,
                scanned: _results.isNotEmpty,
                totalBytes: _totalBytes,
                selectedBytes: _selectedBytes,
                scanProgress: _scanProgress,
                wechatRunning: _wechatRunning,
                onScan: _selectedAccount == null ? null : _startScan,
                onCancel: _requestCancel,
                onClean: _confirmAndClean,
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: const TextStyle(color: AppColors.primary, fontSize: 15),
                ),
              ],
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final table = _PlanCard(
                    items: _results,
                    selectedKeys: _selectedKeys,
                    expandedIds: _expandedIds,
                    scanning: _scanning,
                    activeRuleId: _activeRuleId,
                    onToggleCategory: _toggleCategory,
                    onToggleFile: _toggleFile,
                    onToggleExpand: _toggleExpand,
                  );
                  final side = _SidePanel(
                    selectedBytes: _selectedBytes,
                    selectedFiles: _selectedKeys.length,
                    lastClean: _lastClean,
                    ackHighRisk: _ackHighRisk,
                    showAck: _hasHighRiskSelected,
                    onAckChanged: (value) => setState(() => _ackHighRisk = value),
                  );
                  if (constraints.maxWidth < 1040) {
                    return Column(
                      children: [table, const SizedBox(height: 18), side],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: table),
                      const SizedBox(width: 20),
                      SizedBox(width: 430, child: side),
                    ],
                  );
                },
              ),
            ],
          ),
          if (_cleaning)
            TaskProgressOverlay(
              title: '正在清理微信数据',
              subtitle: '已处理 ${formatWechatBytes(_cleanedBytes)}，可恢复项进入隔离区',
              progress: _cleanProgress,
              icon: Icons.chat_bubble_outline,
            ),
        ],
      ),
    );
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingAccounts = true;
      _message = null;
    });
    final accounts = await _service.discoverAccounts();
    final running = await _service.isWeChatRunning();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _selectedAccount =
          accounts.isEmpty
              ? null
              : accounts.firstWhere(
                (item) => item.id == _selectedAccount?.id,
                orElse: () => accounts.first,
              );
      _wechatRunning = running;
      _loadingAccounts = false;
    });
  }

  Future<void> _selectAccount(WechatAccount account) async {
    setState(() {
      _selectedAccount = account;
      _results = const [];
      _selectedKeys.clear();
      _expandedIds.clear();
      _lastClean = null;
      _message = null;
    });
  }

  Future<void> _addCustomAccount() async {
    final account = await _service.validateCustomRoot(_customPathController.text);
    if (!mounted) return;
    if (account == null) {
      setState(() => _message = '未能识别该目录为微信数据目录，请检查路径结构。');
      return;
    }
    setState(() {
      _accounts = [..._accounts.where((item) => item.id != account.id), account];
      _selectedAccount = account;
      _message = '已添加自定义微信目录：${account.displayName}';
      _customPathController.clear();
    });
  }

  Future<void> _startScan() async {
    final account = _selectedAccount;
    if (account == null || _scanning || _cleaning) return;

    setState(() {
      _scanning = true;
      _cancelRequested = false;
      _activeRuleId = null;
      _lastClean = null;
      _scanProgress = 0;
      _message = null;
      _ackHighRisk = false;
    });

    final running = await _service.isWeChatRunning();
    final results = await _service.scanAccount(
      account,
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
              .where((item) => item.rule.defaultSelected && item.rule.allowClean)
              .expand(
                (item) => item.files.map(
                  (file) => WechatService.selectionKey(item.rule.id, file),
                ),
              ),
        );
      _scanning = false;
      _activeRuleId = null;
      _scanProgress = 1;
      _wechatRunning = running;
      _message =
          running
              ? '检测到微信正在运行：可继续浏览扫描结果，清理前请先退出微信。'
              : null;
    });
  }

  void _requestCancel() {
    setState(() => _cancelRequested = true);
  }

  void _toggleCategory(WechatCategoryResult category, bool selected) {
    if (_scanning || _cleaning || !category.rule.allowClean) return;
    setState(() {
      final keys = category.files.map(
        (file) => WechatService.selectionKey(category.rule.id, file),
      );
      if (selected) {
        _selectedKeys.addAll(keys);
      } else {
        _selectedKeys.removeAll(keys);
      }
    });
  }

  void _toggleFile(WechatCategoryResult category, WechatFileItem file) {
    if (_scanning || _cleaning || !category.rule.allowClean) return;
    final key = WechatService.selectionKey(category.rule.id, file);
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
    if (_selectedKeys.isEmpty || _cleaning || _scanning) return;

    if (_hasHighRiskSelected && !_ackHighRisk) {
      setState(() {
        _message = '已选择高风险资料，请勾选“我已了解删除后可能无法在微信内查看”后再继续。';
      });
      return;
    }

    final confirmed = await showAnimatedAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_hasHighRiskSelected ? '确认清理高风险资料' : '确认开始微信清理'),
          content: Text(
            '将处理 ${formatWechatBytes(_selectedBytes)}，共 ${_selectedKeys.length} 个文件。'
            '${_hasHighRiskSelected ? '\n\n用户资料会优先移入隔离区，隔离期内可在「隔离区」恢复。' : '\n\n安全缓存将直接删除；可恢复项进入隔离区。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开始清理'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    // 确认后再检测进程，避免在弹窗前跨异步间隙使用 BuildContext。
    if (_wechatRunning || await _service.isWeChatRunning()) {
      if (!mounted) return;
      setState(() {
        _wechatRunning = true;
        _message = '微信仍在运行，请先退出微信后再清理（错误码 WX_RUNNING）。';
      });
      return;
    }
    if (!mounted) return;

    final settings = await _settingsService.load();
    setState(() {
      _cleaning = true;
      _cancelRequested = false;
      _lastClean = null;
      _cleanProgress = 0;
      _cleanedBytes = 0;
      _message = null;
    });

    final result = await _service.cleanSelected(
      categories: _results,
      selectedKeys: _selectedKeys,
      quarantineDays: settings.quarantineDays,
      quarantineRoot: settings.quarantinePath,
      shouldCancel: () => _cancelRequested,
      onProgress: (progress, processedBytes) {
        if (!mounted) return;
        setState(() {
          _cleanProgress = progress.clamp(0.0, 1.0).toDouble();
          _cleanedBytes = processedBytes;
        });
      },
    );

    if (!mounted) return;
    if (result.isBlockedByWechat) {
      setState(() {
        _cleaning = false;
        _wechatRunning = true;
        _message = '清理已中止：检测到微信进程（WX_RUNNING）。';
      });
      await showTaskResultDialog(
        context: context,
        kind: TaskResultKind.failure,
        title: '清理失败',
        message: '检测到微信仍在运行，已中止清理。请退出微信后重试。',
        details: const ['错误码：WX_RUNNING'],
      );
      return;
    }
    if (result.isSpaceInsufficient) {
      setState(() {
        _cleaning = false;
        _message =
            '隔离盘空间不足，已停止清理且未永久删除（QUARANTINE_SPACE_INSUFFICIENT）。'
            '请更换隔离位置或减少所选项目。';
      });
      await showTaskResultDialog(
        context: context,
        kind: TaskResultKind.failure,
        title: '清理失败',
        message: '隔离盘空间不足，已停止清理且未永久删除。',
        details: const ['错误码：QUARANTINE_SPACE_INSUFFICIENT', '请更换隔离位置或减少所选项目'],
      );
      return;
    }

    final account = _selectedAccount;
    final refreshed =
        account == null ? const <WechatCategoryResult>[] : await _service.scanAccount(account);

    if (!mounted) return;
    setState(() {
      _lastClean = result;
      _results = refreshed;
      _selectedKeys
        ..clear()
        ..addAll(
          refreshed
              .where((item) => item.rule.defaultSelected && item.rule.allowClean)
              .expand(
                (item) => item.files.map(
                  (file) => WechatService.selectionKey(item.rule.id, file),
                ),
              ),
        );
      _expandedIds.clear();
      _cleaning = false;
      _cleanProgress = 1;
      _message =
          '清理完成：隔离 ${result.quarantinedFiles} 项 / '
          '删除 ${result.deletedFiles} 项，释放 '
          '${formatWechatBytes(result.quarantinedBytes + result.deletedBytes)}';
    });
    await _showWechatCleanResult(result);
  }

  Future<void> _showWechatCleanResult(WechatCleanResult result) async {
    final processed = result.quarantinedFiles + result.deletedFiles;
    final kind = processed <= 0 && result.failedFiles > 0
        ? TaskResultKind.failure
        : (result.failedFiles > 0 || result.skippedFiles > 0
            ? TaskResultKind.partial
            : TaskResultKind.success);
    final title = switch (kind) {
      TaskResultKind.success => '清理成功',
      TaskResultKind.partial => '清理完成（部分未处理）',
      TaskResultKind.failure => '清理失败',
    };
    await showTaskResultDialog(
      context: context,
      kind: kind,
      title: title,
      message:
          '共释放 ${formatWechatBytes(result.quarantinedBytes + result.deletedBytes)}。',
      details: [
        '隔离 ${result.quarantinedFiles} 项',
        '删除 ${result.deletedFiles} 项',
        '失败 ${result.failedFiles} 项',
        '跳过 ${result.skippedFiles} 项',
      ],
    );
  }
}

class _AccountBar extends StatelessWidget {
  const _AccountBar({
    required this.loading,
    required this.accounts,
    required this.selected,
    required this.wechatRunning,
    required this.customController,
    required this.onRefresh,
    required this.onSelect,
    required this.onAddCustom,
  });

  final bool loading;
  final List<WechatAccount> accounts;
  final WechatAccount? selected;
  final bool wechatRunning;
  final TextEditingController customController;
  final VoidCallback onRefresh;
  final ValueChanged<WechatAccount> onSelect;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('微信账号', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (wechatRunning)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '微信运行中',
                    style: TextStyle(
                      color: Color(0xFFC9852A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新识别'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading)
            const LinearProgressIndicator(minHeight: 4)
          else if (accounts.isEmpty)
            const Text(
              '未发现微信账号目录。可手动填写数据目录路径后添加。',
              style: TextStyle(color: AppColors.muted),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final account in accounts)
                  ChoiceChip(
                    label: Text(
                      '${account.displayName}（${account.layout == 'classic' ? '经典' : '新版'}）',
                    ),
                    selected: selected?.id == account.id,
                    onSelected: (_) => onSelect(account),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: customController,
                  decoration: const InputDecoration(
                    hintText: r'手动指定微信数据目录，例如 C:\Users\...\Documents\WeChat Files\wxid_xxx',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: onAddCustom, child: const Text('添加目录')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.scanning,
    required this.cleaning,
    required this.scanned,
    required this.totalBytes,
    required this.selectedBytes,
    required this.scanProgress,
    required this.wechatRunning,
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
  final bool wechatRunning;
  final VoidCallback? onScan;
  final VoidCallback onCancel;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final busy = scanning || cleaning;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('预计可释放', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  scanned ? formatWechatBytes(totalBytes) : '--',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: busy
                        ? scanProgress.clamp(0.02, 1.0).toDouble()
                        : (totalBytes == 0 ? 0 : selectedBytes / totalBytes),
                    minHeight: 10,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  busy
                      ? (scanning ? '正在扫描当前账号的明确规则目录...' : '正在清理，可恢复项进入隔离区...')
                      : '已选择 ${formatWechatBytes(selectedBytes)}；聊天资料默认不选',
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
                if (wechatRunning) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '清理前请退出微信，避免文件锁定或数据不一致。',
                    style: TextStyle(color: Color(0xFFC9852A), fontSize: 14),
                  ),
                ],
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.items,
    required this.selectedKeys,
    required this.expandedIds,
    required this.scanning,
    required this.activeRuleId,
    required this.onToggleCategory,
    required this.onToggleFile,
    required this.onToggleExpand,
  });

  final List<WechatCategoryResult> items;
  final Set<String> selectedKeys;
  final Set<String> expandedIds;
  final bool scanning;
  final String? activeRuleId;
  final void Function(WechatCategoryResult, bool) onToggleCategory;
  final void Function(WechatCategoryResult, WechatFileItem) onToggleFile;
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 42),
              alignment: Alignment.center,
              child: Text(
                scanning ? '正在扫描...' : '选择账号后开始扫描，生成可解释的清理计划',
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (final item in items)
              _CategoryTile(
                item: item,
                selectedKeys: selectedKeys,
                expanded: expandedIds.contains(item.rule.id),
                active: activeRuleId == item.rule.id,
                onToggleCategory: onToggleCategory,
                onToggleFile: onToggleFile,
                onToggleExpand: onToggleExpand,
              ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.item,
    required this.selectedKeys,
    required this.expanded,
    required this.active,
    required this.onToggleCategory,
    required this.onToggleFile,
    required this.onToggleExpand,
  });

  final WechatCategoryResult item;
  final Set<String> selectedKeys;
  final bool expanded;
  final bool active;
  final void Function(WechatCategoryResult, bool) onToggleCategory;
  final void Function(WechatCategoryResult, WechatFileItem) onToggleFile;
  final ValueChanged<String> onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final selectable = item.files.where((_) => item.rule.allowClean).toList();
    final selectedCount =
        selectable
            .where(
              (file) => selectedKeys.contains(
                WechatService.selectionKey(item.rule.id, file),
              ),
            )
            .length;
    final allSelected =
        selectable.isNotEmpty && selectedCount == selectable.length;
    final partial = selectedCount > 0 && !allSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? AppColors.primary : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
        color: active ? AppColors.primarySoft.withValues(alpha: 0.35) : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                tristate: true,
                value: !item.rule.allowClean
                    ? false
                    : (allSelected ? true : (partial ? null : false)),
                onChanged: !item.rule.allowClean
                    ? null
                    : (value) => onToggleCategory(item, value ?? false),
              ),
              UiAssetIcon(
                asset: UiAssets.wechatCategory(item.rule.id),
                fallback: Icons.folder_outlined,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.rule.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.rule.subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              RiskPill(
                label: wechatRiskLabel(item.rule.risk),
                asset: UiAssets.riskBadge(item.rule.risk.name),
              ),
              const SizedBox(width: 12),
              Text(
                formatWechatBytes(item.bytes),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () => onToggleExpand(item.rule.id),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const Divider(height: 18),
            if (!item.rule.allowClean)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '该类仅为占用统计，V1 不提供直接删除。',
                    style: TextStyle(color: Color(0xFFC4554D)),
                  ),
                ),
              ),
            for (final file in item.files.take(80))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Checkbox(
                  value: selectedKeys.contains(
                    WechatService.selectionKey(item.rule.id, file),
                  ),
                  onChanged: !item.rule.allowClean
                      ? null
                      : (_) => onToggleFile(item, file),
                ),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(formatWechatBytes(file.bytes)),
              ),
            if (item.files.length > 80)
              Text(
                '仅展示前 80 个大文件，共 ${item.fileCount} 个',
                style: const TextStyle(color: AppColors.muted),
              ),
          ],
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.selectedBytes,
    required this.selectedFiles,
    required this.lastClean,
    required this.ackHighRisk,
    required this.showAck,
    required this.onAckChanged,
  });

  final int selectedBytes;
  final int selectedFiles;
  final WechatCleanResult? lastClean;
  final bool ackHighRisk;
  final bool showAck;
  final ValueChanged<bool> onAckChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('安全说明', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          const Text('· 不展示联系人与消息正文'),
          const SizedBox(height: 8),
          const Text('· 聊天图片/视频/文件默认不选'),
          const SizedBox(height: 8),
          const Text('· 可恢复项进入隔离区，可按原路径恢复'),
          const SizedBox(height: 8),
          const Text('· 聊天数据库仅统计占用，不直接删除'),
          const SizedBox(height: 18),
          Text(
            '已选 $selectedFiles 个文件 / ${formatWechatBytes(selectedBytes)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (showAck) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: ackHighRisk,
              onChanged: (value) => onAckChanged(value ?? false),
              title: const Text(
                '我已了解删除后可能无法在微信内查看这些资料',
                style: TextStyle(fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          if (lastClean != null) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              '最近任务：隔离 ${lastClean!.quarantinedFiles}，'
              '删除 ${lastClean!.deletedFiles}，'
              '失败 ${lastClean!.failedFiles}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
