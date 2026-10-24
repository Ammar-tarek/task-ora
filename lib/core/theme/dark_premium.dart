// lib/core/theme/dark_premium.dart
// Agreed "Dark Premium" palette tokens. Introduced here so new M2 surfaces can
// preview the direction WITHOUT performing the full theme migration (that is a
// later milestone that will fold these into AppTheme/AppColors).
//
//   background #10151D · cards #1B2430 · borders #303B4A · accent #D9FF65

import 'package:flutter/material.dart';

class DarkPremium {
  DarkPremium._();

  static const Color background = Color(0xFF10151D);
  static const Color card = Color(0xFF1B2430);
  static const Color border = Color(0xFF303B4A);
  static const Color accent = Color(0xFFD9FF65);

  /// Readable on-accent foreground (accent is a bright lime → needs dark text).
  static const Color onAccent = Color(0xFF10151D);
}
