import 'package:flutter/material.dart';

import '../features/cleanup/cleanup_page.dart';
import '../features/dashboard/feature_dashboard.dart';
import '../features/feature_pages.dart';
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

  @override
  Widget build(BuildContext context) {
    final page = featurePages[_selectedIndex];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            TopNavigation(
              selectedIndex: _selectedIndex,
              onSelected: (index) => setState(() => _selectedIndex = index),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(40, 34, 40, 36),
                child: _selectedIndex == 0
                    ? const CleanupPage()
                    : FeatureDashboard(page: page),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
