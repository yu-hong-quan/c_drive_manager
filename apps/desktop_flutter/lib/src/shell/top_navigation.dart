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
    _NavItem(index: 6, label: '关于作者'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? const Color(0xFFE8ECEF) : AppColors.text;
    final borderColor = dark ? const Color(0xFF303A3F) : AppColors.border;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowController.startDrag(),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Text(
              'C 盘管家',
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 34),
            Expanded(
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
            _UtilityNavGroup(
              items: _utilityItems,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
            const SizedBox(width: 20),
            WindowCaptionButton(
              icon: Icons.remove,
              color: textColor,
              onPressed: WindowController.minimize,
            ),
            WindowCaptionButton(
              icon: Icons.crop_square,
              color: textColor,
              onPressed: WindowController.toggleMaximize,
            ),
            WindowCaptionButton(
              icon: Icons.close,
              color: textColor,
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

class _UtilityNavGroup extends StatelessWidget {
  const _UtilityNavGroup({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF303A3F)
        : AppColors.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            for (final item in items)
              _UtilityNavButton(
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

class _UtilityNavButton extends StatelessWidget {
  const _UtilityNavButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TopNavTapTarget(label: label, selected: selected, onTap: onTap);
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
    return _TopNavTapTarget(label: label, selected: selected, onTap: onTap);
  }
}

class _TopNavTapTarget extends StatelessWidget {
  const _TopNavTapTarget({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE8ECEF)
        : AppColors.text;
    return InkResponse(
      onTap: onTap,
      radius: 46,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      child: SizedBox(
        height: 76,
        width: 112,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : textColor,
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
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 28,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Center(child: Icon(icon, size: 24, color: color)),
      ),
    );
  }
}
