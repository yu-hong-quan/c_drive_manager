import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 清理 / 迁移过程中的全页遮罩进度动画。
class TaskProgressOverlay extends StatefulWidget {
  const TaskProgressOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final double progress;
  final IconData icon;

  @override
  State<TaskProgressOverlay> createState() => _TaskProgressOverlayState();
}

class _TaskProgressOverlayState extends State<TaskProgressOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (widget.progress * 100).clamp(0, 100).round();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.42),
          ),
          child: Center(
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.92, end: 1).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1.02).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF1B2327) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: dark ? const Color(0xFF303A3F) : AppColors.border,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x28000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 96,
                            height: 96,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_pulse, _orbit]),
                              builder: (context, child) {
                                return CustomPaint(
                                  painter: _OrbitPainter(
                                    progress: widget.progress.clamp(0.02, 1),
                                    orbit: _orbit.value,
                                    pulse: _pulse.value,
                                  ),
                                  child: Center(
                                    child: Transform.rotate(
                                      angle: math.sin(_orbit.value * math.pi * 2) * 0.08,
                                      child: Icon(
                                        widget.icon,
                                        size: 34,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: dark
                                  ? const Color(0xFFE8ECEF)
                                  : AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: widget.progress.clamp(0.02, 1.0).toDouble(),
                              minHeight: 10,
                              backgroundColor: AppColors.border,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$percent%',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.orbit,
    required this.pulse,
  });

  final double progress;
  final double orbit;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final arc = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      arc,
    );

    final sparkAngle = orbit * math.pi * 2 - math.pi / 2;
    final spark = Offset(
      center.dx + math.cos(sparkAngle) * radius,
      center.dy + math.sin(sparkAngle) * radius,
    );
    canvas.drawCircle(
      spark,
      4 + pulse * 2,
      Paint()..color = AppColors.primary.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.orbit != orbit ||
        oldDelegate.pulse != pulse;
  }
}
