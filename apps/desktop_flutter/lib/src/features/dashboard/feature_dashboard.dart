import 'package:flutter/material.dart';

import '../../models/feature_page_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/risk_pill.dart';

class FeatureDashboard extends StatelessWidget {
  const FeatureDashboard({super.key, required this.page});

  final FeaturePageData page;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(page.title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  page.subtitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    WorkPanel(page: page),
                    const SizedBox(height: 22),
                    ActionPanel(page: page),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: WorkPanel(page: page)),
                  const SizedBox(width: 22),
                  SizedBox(width: 360, child: ActionPanel(page: page)),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const RecentTaskBar(),
        ],
      ),
    );
  }
}

class WorkPanel extends StatelessWidget {
  const WorkPanel({super.key, required this.page});

  final FeaturePageData page;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(page.icon, color: AppColors.primary, size: 34),
              const SizedBox(width: 14),
              Text('建议先处理', style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 24),
          for (final item in page.highlights) ResultRow(label: item),
        ],
      ),
    );
  }
}

class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_box, color: AppColors.primary, size: 26),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const Text(
            '可恢复',
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(width: 32),
          const RiskPill(label: '安全'),
        ],
      ),
    );
  }
}

class ActionPanel extends StatelessWidget {
  const ActionPanel({super.key, required this.page});

  final FeaturePageData page;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page.metricLabel,
            style: const TextStyle(color: AppColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            page.metricValue,
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(page.actionLabel),
            ),
          ),
          const SizedBox(height: 28),
          for (final check in page.checks) SafetyCheck(label: check),
        ],
      ),
    );
  }
}

class SafetyCheck extends StatelessWidget {
  const SafetyCheck({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

class RecentTaskBar extends StatelessWidget {
  const RecentTaskBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: const Row(
        children: [
          Icon(Icons.history, color: AppColors.muted),
          SizedBox(width: 16),
          Text(
            '最近任务',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(width: 28),
          Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Text('7 月 18 日清理完成'),
          Spacer(),
          Text('释放 4.2 GB', style: TextStyle(color: AppColors.muted)),
          SizedBox(width: 12),
          Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}
