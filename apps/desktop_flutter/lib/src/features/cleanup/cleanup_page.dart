import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key});

  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage> {
  bool _scanned = false;
  final Set<String> _selectedIds = {'temp', 'cache'};

  final _items = const <CleanupItem>[
    CleanupItem(
      id: 'temp',
      title: '系统临时文件',
      subtitle: '系统运行产生的临时文件',
      size: '6.8 GB',
      files: '12,453 个',
      recoverable: '可恢复',
      risk: RiskLevel.safe,
      icon: Icons.folder_copy_outlined,
    ),
    CleanupItem(
      id: 'cache',
      title: '应用缓存',
      subtitle: '应用程序缓存文件',
      size: '8.2 GB',
      files: '9,716 个',
      recoverable: '可恢复',
      risk: RiskLevel.safe,
      icon: Icons.layers_outlined,
    ),
    CleanupItem(
      id: 'recycle',
      title: '回收站',
      subtitle: '回收站中的已删除文件',
      size: '3.6 GB',
      files: '1,287 个',
      recoverable: '可恢复',
      risk: RiskLevel.caution,
      icon: Icons.delete_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1386),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(),
          const SizedBox(height: 42),
          DiskSummary(
            scanned: _scanned,
            onScan: () => setState(() => _scanned = true),
          ),
          const SizedBox(height: 34),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: CleanupRecommendationCard(
                  items: _items,
                  selectedIds: _selectedIds,
                  onToggle: _toggleItem,
                ),
              ),
              const SizedBox(width: 20),
              const SizedBox(width: 540, child: SafetyExplanationCard()),
            ],
          ),
          const SizedBox(height: 36),
          const RecentTaskStrip(),
        ],
      ),
    );
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
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
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              '扫描与清理均在本机完成',
              style: TextStyle(color: AppColors.muted, fontSize: 18),
            ),
          ],
        ),
      ],
    );
  }
}

class DiskSummary extends StatelessWidget {
  const DiskSummary({super.key, required this.scanned, required this.onScan});

  final bool scanned;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'C:  476 GB',
                style: TextStyle(fontSize: 24, color: AppColors.text),
              ),
              const SizedBox(height: 12),
              const DiskUsageBar(),
              const SizedBox(height: 26),
              LegendRow(scanned: scanned),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 184,
          margin: const EdgeInsets.symmetric(horizontal: 64),
          color: AppColors.border,
        ),
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '可释放约',
                style: TextStyle(fontSize: 20, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '18.6',
                      style: TextStyle(
                        fontSize: 68,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    TextSpan(
                      text: ' GB',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 256,
                height: 68,
                child: FilledButton(
                  onPressed: onScan,
                  child: Text(scanned ? '重新安全扫描' : '开始安全扫描'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DiskUsageBar extends StatelessWidget {
  const DiskUsageBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 80,
        child: Row(
          children: const [
            DiskSegment(
              widthFactor: 0.34,
              color: Color(0xFF2388EA),
              title: '系统与应用',
              value: '146 GB',
              textColor: Colors.white,
            ),
            DiskSegment(
              widthFactor: 0.17,
              color: Color(0xFF27BFA6),
              title: '用户文件',
              value: '82 GB',
              textColor: Colors.white,
            ),
            DiskSegment(
              widthFactor: 0.35,
              color: Color(0xFFF3F5F6),
              title: '可用',
              value: '239 GB',
              textColor: AppColors.text,
            ),
            DiskSegment(
              widthFactor: 0.14,
              color: Color(0xFFE4E7EA),
              title: '待扫描',
              value: '--',
              textColor: AppColors.text,
              striped: true,
            ),
          ],
        ),
      ),
    );
  }
}

class DiskSegment extends StatelessWidget {
  const DiskSegment({
    super.key,
    required this.widthFactor,
    required this.color,
    required this.title,
    required this.value,
    required this.textColor,
    this.striped = false,
  });

  final double widthFactor;
  final Color color;
  final String title;
  final String value;
  final Color textColor;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (widthFactor * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          backgroundBlendMode: BlendMode.srcOver,
        ),
        child: CustomPaint(
          painter: striped ? StripePainter() : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: textColor, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD3D8DC)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LegendRow extends StatelessWidget {
  const LegendRow({super.key, required this.scanned});

  final bool scanned;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 34,
      runSpacing: 10,
      children: [
        const LegendItem(
          color: Color(0xFF2388EA),
          label: '系统与应用  146 GB（30.7%）',
        ),
        const LegendItem(color: Color(0xFF27BFA6), label: '用户文件  82 GB（17.2%）'),
        const LegendItem(color: Color(0xFFE1E5E8), label: '可用  239 GB（50.2%）'),
        LegendItem(
          color: const Color(0xFFD8DDE1),
          label: scanned ? '待扫描  已完成 18.6 GB' : '待扫描  预计 18.6 GB',
        ),
      ],
    );
  }
}

class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.muted),
        ),
      ],
    );
  }
}

class CleanupRecommendationCard extends StatelessWidget {
  const CleanupRecommendationCard({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<CleanupItem> items;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '建议先处理',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 24),
          const CleanupTableHeader(),
          for (final item in items)
            CleanupTableRow(
              item: item,
              selected: selectedIds.contains(item.id),
              onToggle: () => onToggle(item.id),
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
      padding: EdgeInsets.only(left: 66, right: 4, bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              '项目',
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ),
          Expanded(
            child: Text(
              '大小',
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ),
          Expanded(
            child: Text(
              '文件数',
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ),
          Expanded(
            child: Text(
              '可恢复',
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ),
          SizedBox(width: 78),
        ],
      ),
    );
  }
}

class CleanupTableRow extends StatelessWidget {
  const CleanupTableRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final CleanupItem item;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        height: 92,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            SizedBox(
              width: 54,
              child: Icon(
                item.icon,
                color: item.risk == RiskLevel.caution
                    ? const Color(0xFFFF7A1A)
                    : AppColors.primary,
                size: 40,
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                item.size,
                style: const TextStyle(fontSize: 16, color: AppColors.text),
              ),
            ),
            Expanded(
              child: Text(
                item.files,
                style: const TextStyle(fontSize: 16, color: AppColors.text),
              ),
            ),
            Expanded(
              child: Text(
                item.recoverable,
                style: const TextStyle(fontSize: 16, color: AppColors.text),
              ),
            ),
            SizedBox(width: 78, child: RiskBadge(level: item.risk)),
          ],
        ),
      ),
    );
  }
}

class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final caution = level == RiskLevel.caution;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: caution ? const Color(0xFFFFF1CE) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        caution ? '谨慎' : '安全',
        style: TextStyle(
          color: caution ? const Color(0xFFE38400) : AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class SafetyExplanationCard extends StatelessWidget {
  const SafetyExplanationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(34, 28, 34, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '安全说明',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 30),
          SafetyPoint(title: '高风险资料默认不选', body: '系统文件、关键配置等高风险资料默认不选，确保系统稳定。'),
          SafetyPoint(title: '清理前预览', body: '扫描完成后可查看详细内容，手动选择后再清理。'),
          SafetyPoint(title: '隔离区保留 7 天', body: '清理的文件将进入隔离区，保留 7 天，可随时恢复。'),
          SizedBox(height: 12),
          Text(
            '了解清理规则  ›',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF1677D2),
              fontWeight: FontWeight.w600,
            ),
          ),
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
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
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
  const RecentTaskStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: const Row(
        children: [
          Icon(Icons.history, color: AppColors.muted, size: 28),
          SizedBox(width: 18),
          Text(
            '最近任务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          SizedBox(width: 30),
          Icon(Icons.check_circle, color: AppColors.primary, size: 22),
          SizedBox(width: 10),
          Text(
            '7 月 18 日清理完成',
            style: TextStyle(fontSize: 16, color: AppColors.text),
          ),
          SizedBox(width: 70),
          Text(
            '释放 4.2 GB',
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          Spacer(),
          Icon(Icons.chevron_right, color: AppColors.muted, size: 30),
        ],
      ),
    );
  }
}

class CleanupItem {
  const CleanupItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.size,
    required this.files,
    required this.recoverable,
    required this.risk,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String size;
  final String files;
  final String recoverable;
  final RiskLevel risk;
  final IconData icon;
}

enum RiskLevel { safe, caution }
