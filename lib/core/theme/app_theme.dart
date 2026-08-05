import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
// Brand + status colours are compile-time constants (same in light & dark).
// Surface / text / outline colours are MUTABLE statics that [setDarkMode]
// swaps at runtime so every screen that references them updates instantly.
class AppColors {
  AppColors._();

  static bool _dark = false;
  static bool get isDark => _dark;

  // ── Constant brand / status colours (identical in both modes) ──────────────
  static const Color gold = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFFED977);
  static const Color goldDark = Color(0xFF755B00);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);

  static const Color secondary = Color(0xFFC9A84C);
  static const Color onSecondary = Color(0xFF000000);
  static const Color secondaryContainer = Color(0xFF262010);
  static const Color onSecondaryContainer = Color(0xFFFED977);

  // Status colours
  static const Color statusDone = Color(0xFF2E7D32);
  static const Color statusInProgress = Color(0xFF1565C0);
  static const Color statusTodo = Color(0xFF6D4C41);
  static const Color statusBlocked = Color(0xFFBA1A1A);
  static const Color statusLow = Color(0xFF2E7D32);
  static const Color statusMedium = Color(0xFF755B00);
  static const Color statusHigh = Color(0xFFBA1A1A);

  // ── Mutable theme-sensitive colours (swapped by [setDarkMode]) ─────────────
  static Color primary = const Color(0xFF121212);
  static Color onPrimary = const Color(0xFFFFFFFF);
  static Color primaryContainer = const Color(0xFFF6F2E7);

  static Color background = const Color(0xFFF8F9FA);
  static Color surface = const Color(0xFFFFFFFF);
  static Color surfaceHigh = const Color(0xFFEEEEEE);
  static Color surfaceContainerLow = const Color(0xFFF3F3F3);
  static Color surfaceContainerLowest = const Color(0xFFFFFFFF);

  static Color onSurface = const Color(0xFF1C1B1B);
  static Color onSurfaceVariant = const Color(0xFF555555);
  static Color outline = const Color(0xFFCCCCCC);
  static Color outlineVariant = const Color(0xFFE0E0E0);

  static Color errorContainer = const Color(0xFFFFDAD6);

  /// Swap the mutable palette between light and dark (Black & Gold theme).
  static void setDarkMode(bool dark) {
    _dark = dark;
    if (dark) {
      primary = const Color(0xFFD4AF37); // Premium Gold
      onPrimary = const Color(0xFF000000); // Black text/icons on Gold primary
      primaryContainer = const Color(0xFF262010);
      background = const Color(0xFF0C0C0C); // Pitch / Near Black
      surface = const Color(0xFF161616); // Dark Gray
      surfaceHigh = const Color(0xFF242424); // Dark Charcoal
      surfaceContainerLow = const Color(0xFF121212);
      surfaceContainerLowest = const Color(0xFF1E1E1E); // Input / Card container fill
      onSurface = const Color(0xFFF5F5F5); // Crisp White
      onSurfaceVariant = const Color(0xFFA0A0A0); // Light Gray
      outline = const Color(0xFF3E3E3E);
      outlineVariant = const Color(0xFF2A2A2A);
      errorContainer = const Color(0xFF3C1418);
    } else {
      primary = const Color(0xFF121212); // Deep Black
      onPrimary = const Color(0xFFFFFFFF); // White text/icons on Black primary
      primaryContainer = const Color(0xFFF6F2E7);
      background = const Color(0xFFF8F9FA);
      surface = const Color(0xFFFFFFFF);
      surfaceHigh = const Color(0xFFEEEEEE);
      surfaceContainerLow = const Color(0xFFF3F3F3);
      surfaceContainerLowest = const Color(0xFFFFFFFF);
      onSurface = const Color(0xFF1C1B1B);
      onSurfaceVariant = const Color(0xFF555555);
      outline = const Color(0xFFCCCCCC);
      outlineVariant = const Color(0xFFE0E0E0);
      errorContainer = const Color(0xFFFFDAD6);
    }
  }
}

// ── Text Styles ───────────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // Getters so the baked-in colour follows the active theme mode dynamically.
  static TextStyle get displayLg => GoogleFonts.playfairDisplay(
    fontSize: 42,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.84,
    color: AppColors.onSurface,
  );
  static TextStyle get displayMd => GoogleFonts.playfairDisplay(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.32,
    color: AppColors.onSurface,
  );
  static TextStyle get headlineLg => GoogleFonts.playfairDisplay(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get headlineMd => GoogleFonts.playfairDisplay(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get headlineSm => GoogleFonts.playfairDisplay(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get bodyLg => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.onSurface,
  );
  static TextStyle get bodyMd => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.onSurface,
  );
  static TextStyle get bodySm => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.onSurfaceVariant,
  );
  static TextStyle get labelCaps => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.2,
    color: AppColors.onSurfaceVariant,
  );
  static TextStyle get labelMd => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.onSurface,
  );
  static TextStyle get dataLg => GoogleFonts.jetBrainsMono(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onSurface,
  );
  static TextStyle get dataMd => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onSurface,
  );
  static TextStyle get dataSm => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onSurfaceVariant,
  );
}

// ── Theme ─────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  /// Kept for backwards-compatibility — resolves to the current mode's theme.
  static ThemeData get light => build(false);
  static ThemeData get dark => build(true);

  /// Builds a ThemeData for light or dark mode.
  static ThemeData build([bool? isDark]) {
    final dark = isDark ?? AppColors.isDark;
    AppColors.setDarkMode(dark);
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final navSelected = dark ? AppColors.gold : AppColors.primary;

    final textTheme = TextTheme(
      displayLarge: AppTextStyles.displayLg,
      displayMedium: AppTextStyles.displayMd,
      headlineLarge: AppTextStyles.headlineLg,
      headlineMedium: AppTextStyles.headlineMd,
      headlineSmall: AppTextStyles.headlineSm,
      titleLarge: AppTextStyles.headlineSm,
      titleMedium: AppTextStyles.bodyMd,
      titleSmall: AppTextStyles.bodySm,
      bodyLarge: AppTextStyles.bodyLg,
      bodyMedium: AppTextStyles.bodyMd,
      bodySmall: AppTextStyles.bodySm,
      labelLarge: AppTextStyles.labelMd,
      labelMedium: AppTextStyles.labelMd,
      labelSmall: AppTextStyles.labelCaps,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surfaceContainerLowest,
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
      ),
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            brightness: dark ? Brightness.dark : Brightness.light,
            primary: AppColors.primary,
            onPrimary: AppColors.onPrimary,
            primaryContainer: AppColors.primaryContainer,
            onPrimaryContainer: dark ? const Color(0xFFFED977) : AppColors.onSecondaryContainer,
            secondary: AppColors.secondary,
            onSecondary: AppColors.onSecondary,
            secondaryContainer: AppColors.secondaryContainer,
            onSecondaryContainer: AppColors.onSecondaryContainer,
            surface: AppColors.surface,
            onSurface: AppColors.onSurface,
            onSurfaceVariant: AppColors.onSurfaceVariant,
            surfaceContainerLow: AppColors.surfaceContainerLow,
            surfaceContainerLowest: AppColors.surfaceContainerLowest,
            surfaceContainerHigh: AppColors.surfaceHigh,
            outline: AppColors.outline,
            outlineVariant: AppColors.outlineVariant,
            error: AppColors.error,
            onError: AppColors.onError,
            errorContainer: AppColors.errorContainer,
          ),
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: AppColors.gold.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.gold,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.outline.withValues(alpha: 0.1),
        iconTheme: IconThemeData(color: AppColors.onSurface),
        titleTextStyle: AppTextStyles.headlineSm.copyWith(fontSize: 19, color: AppColors.onSurface),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.outlineVariant),
        ),
        titleTextStyle: AppTextStyles.headlineSm.copyWith(color: AppColors.onSurface),
        contentTextStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        modalBackgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.outlineVariant),
        ),
        textStyle: AppTextStyles.bodyMd,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.gold,
        unselectedLabelColor: AppColors.onSurfaceVariant,
        indicatorColor: AppColors.gold,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTextStyles.bodySm,
      ),
      iconTheme: IconThemeData(
        color: AppColors.onSurface,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: AppColors.onSurfaceVariant,
        textColor: AppColors.onSurface,
        selectedColor: AppColors.gold,
        selectedTileColor: AppColors.gold.withValues(alpha: 0.1),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: AppTextStyles.labelMd.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: AppTextStyles.labelMd.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.gold),
          textStyle: AppTextStyles.labelMd.copyWith(
            fontSize: 14,
            color: AppColors.gold,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.gold,
          textStyle: AppTextStyles.labelMd.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: const Color(0xFF000000),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        labelStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        floatingLabelStyle: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
        hintStyle: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        helperStyle: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        errorStyle: AppTextStyles.bodySm.copyWith(color: AppColors.error),
        prefixIconColor: AppColors.onSurfaceVariant,
        suffixIconColor: AppColors.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        labelStyle: AppTextStyles.bodySm,
        secondaryLabelStyle: AppTextStyles.bodySm.copyWith(color: AppColors.gold),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF242424) : AppColors.primary,
        contentTextStyle: AppTextStyles.bodyMd.copyWith(color: Colors.white),
        actionTextColor: AppColors.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.gold;
          return AppColors.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary.withValues(alpha: 0.5);
          return AppColors.surface;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.gold;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(const Color(0xFF000000)),
        side: BorderSide(color: AppColors.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.gold;
          return AppColors.outline;
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        selectedItemColor: navSelected,
        unselectedItemColor: AppColors.onSurfaceVariant,
        selectedLabelStyle: AppTextStyles.bodySm.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.bodySm.copyWith(fontSize: 11),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

/// Gold status chip
class TStatusChip extends StatelessWidget {
  const TStatusChip({super.key, required this.label, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final c = color ?? AppColors.gold;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6 : 8,
        vertical: isMobile ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 5 : 6,
            height: isMobile ? 5 : 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          SizedBox(width: isMobile ? 3 : 5),
          Text(
            S.t(label),
            style: AppTextStyles.bodySm.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
              fontSize: isMobile ? 9.5 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Priority badge
class TPriorityBadge extends StatelessWidget {
  const TPriorityBadge({super.key, required this.priority});
  final String priority; // 'High' | 'Medium' | 'Low'
  Color get _color {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'critical':
      case 'urgent':
      case 'عالية':
      case 'عاجلة':
      case 'حرجة':
        return AppColors.statusHigh;
      case 'medium':
      case 'متوسطة':
        return AppColors.statusMedium;
      default:
        return AppColors.statusLow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final c = _color;

    IconData flagIcon;
    switch (priority.toLowerCase()) {
      case 'high':
      case 'critical':
      case 'urgent':
      case 'عالية':
      case 'عاجلة':
      case 'حرجة':
        flagIcon = Icons.flag_rounded;
        break;
      case 'medium':
      case 'متوسطة':
        flagIcon = Icons.flag_outlined;
        break;
      default:
        flagIcon = Icons.outlined_flag;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6 : 8,
        vertical: isMobile ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(flagIcon, size: isMobile ? 10 : 12, color: c),
          SizedBox(width: isMobile ? 3 : 4),
          Text(
            S.t(priority),
            style: AppTextStyles.bodySm.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
              fontSize: isMobile ? 9.5 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat card — used on dashboards
class TStatCard extends StatelessWidget {
  const TStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.sub,
    this.accent = false,
    this.onTap,
  });
  final String title, value;
  final IconData icon;
  final String? sub;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    // In dark mode, accent card background is AppColors.primary (Gold 0xFFD4AF37).
    // All text, numbers, and icons inside a Gold container must be crisp Deep Black.
    final isGoldBackground = accent && isDark;

    final iconColor = accent
        ? (isGoldBackground ? const Color(0xFF000000) : AppColors.gold)
        : AppColors.gold;

    final subColor = accent
        ? (isGoldBackground ? const Color(0x99000000) : Colors.white54)
        : null;

    final valueColor = accent
        ? (isGoldBackground ? const Color(0xFF000000) : AppColors.gold)
        : AppColors.onSurface;

    final titleColor = accent
        ? (isGoldBackground ? const Color(0xCC000000) : Colors.white60)
        : AppColors.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent
                ? AppColors.primary
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accent ? Colors.transparent : AppColors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const Spacer(),
                  if (sub != null)
                    Flexible(
                      child: Text(
                        S.t(sub!),
                        style: AppTextStyles.bodySm.copyWith(
                          color: subColor,
                          fontSize: 11,
                          fontWeight: isGoldBackground ? FontWeight.w600 : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTextStyles.dataLg.copyWith(
                    fontSize: 22,
                    color: valueColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                S.t(title),
                style: AppTextStyles.labelCaps.copyWith(
                  fontSize: 9,
                  color: titleColor,
                  fontWeight: isGoldBackground ? FontWeight.w800 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header with optional action
class TSectionHeader extends StatelessWidget {
  const TSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(S.t(title), style: AppTextStyles.headlineSm),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              S.t(action!),
              style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
            ),
          ),
      ],
    );
  }
}

/// Avatar with initials
class TAvatar extends StatelessWidget {
  const TAvatar({super.key, required this.name, this.size = 36});
  final String name;
  final double size;
  Color get _bg {
    final colors = [
      const Color(0xFF1A237E),
      const Color(0xFF4A148C),
      const Color(0xFF880E4F),
      const Color(0xFF004D40),
      const Color(0xFF1B5E20),
      const Color(0xFFE65100),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
      child: Center(
        child: Text(
          _initials,
          style: AppTextStyles.labelMd.copyWith(
            color: Colors.white,
            fontSize: size * 0.33,
          ),
        ),
      ),
    );
  }
}

/// Custom scroll behavior enabling drag-scrolling across all devices (mouse, trackpad, touch, stylus).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

