import 'package:flutter/material.dart';

import 'shell/manager_shell.dart';
import 'theme/app_theme.dart';

/// Root application shell for the C 盘管家 desktop client.
class CDriveManagerApp extends StatelessWidget {
  const CDriveManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'C 盘管家',
      theme: AppTheme.light(),
      home: const ManagerShell(),
    );
  }
}
