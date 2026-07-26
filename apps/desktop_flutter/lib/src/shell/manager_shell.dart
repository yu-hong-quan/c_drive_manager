import 'package:flutter/material.dart';

import '../features/cleanup/cleanup_page.dart';
import '../features/dashboard/feature_dashboard.dart';
import '../features/feature_pages.dart';
import '../features/settings/settings_page.dart';
import '../features/system_info/system_info_page.dart';
import '../theme/app_colors.dart';
import 'top_navigation.dart';

/// Main desktop frame with product navigation and feature pages.
class ManagerShell extends StatefulWidget {
  const ManagerShell({super.key});

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  int _selectedIndex = 0;
  final ScrollController _pageScrollController = ScrollController();

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = featurePages[_selectedIndex];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.windowBorder),
        ),
        child: SafeArea(
          child: Column(
            children: [
              TopNavigation(
                selectedIndex: _selectedIndex,
                onSelected: (index) => setState(() => _selectedIndex = index),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _pageScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _pageScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(40, 34, 40, 36),
                    child: switch (_selectedIndex) {
                      0 => const CleanupPage(),
                      3 => const SystemInfoPage(),
                      5 => const SettingsPage(),
                      _ => FeatureDashboard(page: page),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
