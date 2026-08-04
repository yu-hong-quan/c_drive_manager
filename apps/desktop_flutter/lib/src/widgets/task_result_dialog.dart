import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'animated_app_dialog.dart';

/// 任务结束态：全部成功 / 部分失败 / 全部失败。
enum TaskResultKind { success, partial, failure }

/// 展示清理或迁移结束后的成功/失败状态。
Future<void> showTaskResultDialog({
  required BuildContext context,
  required TaskResultKind kind,
  required String title,
  required String message,
  List<String> details = const [],
}) {
  return showAnimatedAppDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(28, 28, 28, 18),
        content: _TaskResultBody(
          kind: kind,
          title: title,
          message: message,
          details: details,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

class _TaskResultBody extends StatefulWidget {
  const _TaskResultBody({
    required this.kind,
    required this.title,
    required this.message,
    required this.details,
  });

  final TaskResultKind kind;
  final String title;
  final String message;
  final List<String> details;

  @override
  State<_TaskResultBody> createState() => _TaskResultBodyState();
}

class _TaskResultBodyState extends State<_TaskResultBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.kind) {
      TaskResultKind.success => AppColors.primary,
      TaskResultKind.partial => const Color(0xFFC9852A),
      TaskResultKind.failure => const Color(0xFFD93025),
    };
    final icon = switch (widget.kind) {
      TaskResultKind.success => Icons.check_circle_rounded,
      TaskResultKind.partial => Icons.warning_amber_rounded,
      TaskResultKind.failure => Icons.cancel_rounded,
    };

    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
              if (widget.details.isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in widget.details.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '· $line',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
