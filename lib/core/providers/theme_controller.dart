// lib/core/providers/theme_controller.dart
// Holds the light/dark preference, persists it, and keeps the AppColors
// palette in sync. Notifies listeners so MaterialApp rebuilds with the new theme.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

const _kDarkMode = 'dark_mode_enabled';

class ThemeController extends ChangeNotifier {
  bool _dark = false;
  bool get isDark => _dark;

  ThemeController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _dark = p.getBool(_kDarkMode) ?? false;
    } catch (_) {
      _dark = false;
    }
    AppColors.setDarkMode(_dark);
    notifyListeners();
  }

  /// Toggle dark mode, update the palette, persist, and rebuild the UI.
  Future<void> setDark(bool value) async {
    if (_dark == value) return;
    _dark = value;
    AppColors.setDarkMode(value);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kDarkMode, value);
    } catch (_) {}
  }
}
