import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

class AboutAuthorPage extends StatelessWidget {
  const AboutAuthorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关于作者', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '一个认真打磨 Windows 本地工具体验的开发者',
                  style: TextStyle(color: AppColors.muted, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final profile = _ProfileCard();
              final details = _DetailsCard();
              if (constraints.maxWidth < 920) {
                return Column(
                  children: [profile, const SizedBox(height: 18), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 360, child: profile),
                  const SizedBox(width: 20),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '小',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '小鱼',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'C 盘管家作者 / 独立开发者',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 20),
          const _InfoLine(
            icon: Icons.place_outlined,
            label: '定位',
            value: 'Windows 本地效率工具',
          ),
          const _InfoLine(
            icon: Icons.security_outlined,
            label: '原则',
            value: '离线、安全、可回滚',
          ),
          const _InfoLine(
            icon: Icons.favorite_border,
            label: '偏好',
            value: '干净界面，不做广告弹窗',
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE8ECEF)
        : AppColors.text;
    return AppCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('项目说明', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
            'C 盘管家专注于 Windows C 盘空间管理，核心目标不是“尽可能多删”，'
            '而是让每次清理、迁移和恢复都有明确边界、可解释计划和可追踪结果。',
            style: TextStyle(fontSize: 16, height: 1.55, color: textColor),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('当前版本关注'),
          const _Bullet('安全清理：先扫描、再确认，高风险默认不勾选。'),
          const _Bullet('应用迁移：先生成事务计划，再执行复制、校验、备份和链接。'),
          const _Bullet('隐私边界：扫描与日志优先本地处理，不上传路径和文件名。'),
          const SizedBox(height: 22),
          const _SectionTitle('作者寄语'),
          const Text(
            '如果一个工具能少一点打扰、多一点确定性，它就已经帮用户省下不少心力。',
            style: TextStyle(
              fontSize: 16,
              height: 1.55,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
