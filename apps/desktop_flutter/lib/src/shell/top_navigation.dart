import 'package:flutter/material.dart';

import '../platform/window_controller.dart';
import '../theme/app_colors.dart';

class TopNavigation extends StatelessWidget {
  const TopNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = ['清理', '应用迁移', '微信专清', '系统信息', '隔离区', '设置'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowController.startDrag(),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 36, height: 36),
            const SizedBox(width: 12),
            const Text(
              'C盘管家',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 28),
            Expanded(
              // Flutter owns tab clicks; dragging is triggered only after a pan starts.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      NavButton(
                        label: _items[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            WindowCaptionButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: WindowController.minimize,
            ),
            WindowCaptionButton(
              icon: Icons.crop_square,
              tooltip: '最大化/还原',
              onPressed: WindowController.toggleMaximize,
            ),
            WindowCaptionButton(
              icon: Icons.close,
              tooltip: '关闭',
              onPressed: WindowController.close,
            ),
          ],
        ),
      ),
    );
  }
}

class NavButton extends StatelessWidget {
  const NavButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 76,
        width: 112,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.text,
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: selected ? 72 : 0,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class WindowCaptionButton extends StatelessWidget {
  const WindowCaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(child: Icon(icon, size: 24, color: AppColors.text)),
        ),
      ),
    );
  }
}
