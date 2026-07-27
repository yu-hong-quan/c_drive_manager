import 'package:flutter/material.dart';

import 'shell/manager_shell.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Root application shell for the C 盘管家 desktop client.
class CDriveManagerApp extends StatefulWidget {
  const CDriveManagerApp({super.key});

  @override
  State<CDriveManagerApp> createState() => _CDriveManagerAppState();
}

class _CDriveManagerAppState extends State<CDriveManagerApp> {
  final AppThemeController _themeController = AppThemeController.instance;

  @override
  void initState() {
    super.initState();
    _themeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'C 盘管家',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _themeController.themeMode,
          home: const ManagerShell(),
        );
      },
    );
  }
}
