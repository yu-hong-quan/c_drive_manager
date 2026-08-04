import 'package:flutter/material.dart';

import '../features/about/about_author_page.dart';
import '../features/app_migration/app_migration_page.dart';
import '../features/cleanup/cleanup_page.dart';
import '../features/dashboard/feature_dashboard.dart';
import '../features/feature_pages.dart';
import '../features/quarantine/quarantine_page.dart';
import '../features/settings/settings_page.dart';
import '../features/system_info/system_info_page.dart';
import '../features/wechat/wechat_page.dart';
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
    final page = _selectedIndex < featurePages.length
        ? featurePages[_selectedIndex]
        : featurePages.last;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: dark ? const Color(0xFF303A3F) : AppColors.windowBorder,
          ),
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
                      1 => const AppMigrationPage(),
                      2 => const WechatPage(),
                      3 => const SystemInfoPage(),
                      4 => const QuarantinePage(),
                      5 => const SettingsPage(),
                      6 => const AboutAuthorPage(),
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
