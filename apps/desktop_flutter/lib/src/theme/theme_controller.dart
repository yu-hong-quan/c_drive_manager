import 'package:flutter/material.dart';

import '../features/settings/settings_service.dart';

/// Global theme state backed by the same local settings file as the settings UI.
class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  final SettingsService _settingsService = SettingsService();
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final settings = await _settingsService.load();
    _themeMode = settings.themeMode == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setThemeMode(String value, {bool persist = true}) async {
    final nextMode = value == 'dark' ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == nextMode) return;
    _themeMode = nextMode;
    notifyListeners();
    if (persist) {
      final settings = await _settingsService.load();
      await _settingsService.save(settings.copyWith(themeMode: value));
    }
  }
}
