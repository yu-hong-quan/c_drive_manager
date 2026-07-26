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

  static const _mainItems = ['清理', '应用迁移', '微信专清', '系统信息'];
  static const _utilityItems = [
    _NavItem(index: 4, label: '隔离区'),
    _NavItem(index: 5, label: '设置'),
  ];

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
            SizedBox(
              width: 36,
              height: 36,
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            const Text(
              'C 盘管家',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 34),
            Expanded(
              // Main feature tabs stay with the product area; utility tabs are
              // visually separated on the right before the window controls.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _mainItems.length; i++)
                      NavButton(
                        label: _mainItems[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            UtilityNavGroup(
              items: _utilityItems,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
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

class _NavItem {
  const _NavItem({required this.index, required this.label});

  final int index;
  final String label;
}

class UtilityNavGroup extends StatelessWidget {
  const UtilityNavGroup({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            for (final item in items)
              UtilityNavButton(
                label: item.label,
                selected: selectedIndex == item.index,
                onTap: () => onSelected(item.index),
              ),
          ],
        ),
      ),
    );
  }
}

class UtilityNavButton extends StatelessWidget {
  const UtilityNavButton({
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.text,
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Positioned(
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: selected ? 72 : 0,
                color: AppColors.primary,
              ),
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.text,
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Positioned(
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: selected ? 72 : 0,
                color: AppColors.primary,
              ),
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
