import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'system_info_service.dart';

class SystemInfoPage extends StatefulWidget {
  const SystemInfoPage({super.key});

  @override
  State<SystemInfoPage> createState() => _SystemInfoPageState();
}

class _SystemInfoPageState extends State<SystemInfoPage> {
  final SystemInfoService _service = SystemInfoService();
  late Future<SystemInfoSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _service.load();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1360),
      child: FutureBuilder<SystemInfoSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                loading: snapshot.connectionState != ConnectionState.done,
                onRefresh: _refresh,
              ),
              const SizedBox(height: 24),
              if (snapshot.hasError)
                _ErrorState(onRefresh: _refresh)
              else if (!snapshot.hasData)
                const _LoadingState()
              else
                _SystemInfoContent(snapshot: snapshot.data!),
            ],
          );
        },
      ),
    );
  }

  void _refresh() {
    setState(() => _snapshot = _service.load());
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.loading, required this.onRefresh});

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('系统信息', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    '仅本机读取，不展示敏感序列号',
                    style: TextStyle(color: AppColors.muted, fontSize: 17),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('刷新'),
          ),
        ),
      ],
    );
  }
}

class _SystemInfoContent extends StatelessWidget {
  const _SystemInfoContent({required this.snapshot});

  final SystemInfoSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 980 ? 1 : 2;
            return GridView.count(
              crossAxisCount: columns,
              childAspectRatio: columns == 1 ? 4.3 : 2.35,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _InfoGroupCard(
                  icon: Icons.desktop_windows_outlined,
                  group: snapshot.system,
                ),
                _InfoGroupCard(
                  icon: Icons.memory_outlined,
                  group: snapshot.cpu,
                ),
                _MemoryCard(memory: snapshot.memory),
                _DisplayCard(displays: snapshot.displays),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _DiskSection(disks: snapshot.disks),
      ],
    );
  }
}

class _InfoGroupCard extends StatelessWidget {
  const _InfoGroupCard({required this.icon, required this.group});

  final IconData icon;
  final SystemInfoGroup group;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(icon: icon, title: group.title),
          const SizedBox(height: 16),
          for (final entry in group.values.entries)
            _KeyValue(label: entry.key, value: entry.value),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory});

  final MemoryInfo memory;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.storage_outlined, title: '内存'),
          const SizedBox(height: 16),
          _UsageBar(value: memory.usageRatio),
          const SizedBox(height: 14),
          _KeyValue(label: '总量', value: formatBytes(memory.totalBytes)),
          _KeyValue(label: '已用', value: formatBytes(memory.usedBytes)),
          _KeyValue(label: '可用', value: formatBytes(memory.freeBytes)),
        ],
      ),
    );
  }
}

class _DisplayCard extends StatelessWidget {
  const _DisplayCard({required this.displays});

  final List<DisplayInfo> displays;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.monitor_outlined, title: '显示器'),
          const SizedBox(height: 16),
          if (displays.isEmpty)
            const _KeyValue(label: '设备', value: '未知')
          else
            for (final display in displays.take(2))
              _KeyValue(
                label: display.name,
                value: '${display.resolution} / ${display.refreshRate}',
              ),
        ],
      ),
    );
  }
}

class _DiskSection extends StatelessWidget {
  const _DiskSection({required this.disks});

  final List<DiskInfo> disks;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.sd_storage_outlined, title: '磁盘'),
          const SizedBox(height: 18),
          if (disks.isEmpty)
            const Text('未读取到本地固定磁盘', style: TextStyle(color: AppColors.muted))
          else
            for (final disk in disks) _DiskRow(disk: disk),
        ],
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({required this.disk});

  final DiskInfo disk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              disk.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: _UsageBar(value: disk.usageRatio)),
          const SizedBox(width: 18),
          SizedBox(
            width: 120,
            child: Text(
              disk.fileSystem,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          SizedBox(
            width: 260,
            child: Text(
              '${formatBytes(disk.usedBytes)} 已用 / ${formatBytes(disk.freeBytes)} 可用',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        minHeight: 10,
        value: clampedValue,
        backgroundColor: AppColors.border,
        color: clampedValue > 0.85
            ? const Color(0xFFE38400)
            : AppColors.primary,
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD93025), size: 42),
          const SizedBox(height: 12),
          const Text('系统信息读取失败'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
