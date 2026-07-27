import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: dark ? const Color(0xFF2A3438) : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: dark ? const Color(0xFFE8ECEF) : AppColors.text,
        ),
        child: IconTheme.merge(
          data: IconThemeData(
            color: dark ? const Color(0xFFE8ECEF) : AppColors.text,
          ),
          child: child,
        ),
      ),
    );
  }
}
