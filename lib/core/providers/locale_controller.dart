// lib/core/providers/locale_controller.dart
// Holds the app language (en/ar), persists it, keeps S.lang in sync, and
// rebuilds MaterialApp so locale + text direction (RTL for Arabic) update.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

const _kAppLang = 'app_language';

class LocaleController extends ChangeNotifier {
  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  LocaleController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final code = p.getString(_kAppLang) ?? 'en';
      _locale = Locale(code);
    } catch (_) {}
    S.lang = _locale.languageCode;
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (code == _locale.languageCode) return;
    _locale = Locale(code);
    S.lang = code;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kAppLang, code);
    } catch (_) {}
  }
}
