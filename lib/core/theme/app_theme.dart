import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
// Brand + status colours are compile-time constants (same in light & dark).
// Surface / text / outline colours are MUTABLE statics that [setDarkMode]
// swaps at runtime so every screen that references them updates instantly.
class AppColors {
  AppColors._();

  static bool _dark = false;
  static bool get isDark => _dark;

  // ── Constant brand / status colours (identical in both modes) ──────────────
  static const Color onPrimary          = Color(0xFFFFFFFF);

  static const Color gold               = Color(0xFFC9A84C);
  static const Color goldLight          = Color(0xFFFED977);
  static const Color goldDark           = Color(0xFF755B00);

  static const Color error             = Color(0xFFBA1A1A);
  static const Color onError           = Color(0xFFFFFFFF);

  static const Color secondary         = Color(0xFF755B00);
  static const Color onSecondary       = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFFED977);
  static const Color onSecondaryContainer = Color(0xFF785D00);

  // Status colours
  static const Color statusDone       = Color(0xFF2E7D32);
  static const Color statusInProgress = Color(0xFF1565C0);
  static const Color statusTodo       = Color(0xFF6D4C41);
  static const Color statusBlocked   = Color(0xFFBA1A1A);
  static const Color statusLow       = Color(0xFF2E7D32);
  static const Color statusMedium    = Color(0xFF755B00);
  static const Color statusHigh      = Color(0xFFBA1A1A);

  // ── Mutable theme-sensitive colours (swapped by [setDarkMode]) ─────────────
  static Color primary            = const Color(0xFF000000);
  static Color primaryContainer   = const Color(0xFF1C1B1B);

  static Color background         = const Color(0xFFFDF8F8);
  static Color surface            = const Color(0xFFF1EDEC);
  static Color surfaceHigh        = const Color(0xFFEBE7E6);
  static Color surfaceContainerLow    = const Color(0xFFF7F3F2);
  static Color surfaceContainerLowest = const Color(0xFFFFFFFF);

  static Color onSurface         = const Color(0xFF1C1B1B);
  static Color onSurfaceVariant  = const Color(0xFF444748);
  static Color outline           = const Color(0xFF747878);
  static Color outlineVariant    = const Color(0xFFC4C7C7);

  static Color errorContainer    = const Color(0xFFFFDAD6);

  /// Swap the mutable palette between light and dark.
  static void setDarkMode(bool dark) {
    _dark = dark;
    if (dark) {
      primary               = const Color(0xFF2A2622);
      primaryContainer      = const Color(0xFF35312C);
      background            = const Color(0xFF141312);
      surface               = const Color(0xFF201E1C);
      surfaceHigh           = const Color(0xFF2A2725);
      surfaceContainerLow   = const Color(0xFF1A1817);
      surfaceContainerLowest = const Color(0xFF232120);
      onSurface             = const Color(0xFFEDE8E5);
      onSurfaceVariant      = const Color(0xFFB4AFAC);
      outline               = const Color(0xFF938E8B);
      outlineVariant        = const Color(0xFF3B3836);
      errorContainer        = const Color(0xFF5A1A16);
    } else {
      primary               = const Color(0xFF000000);
      primaryContainer      = const Color(0xFF1C1B1B);
      background            = const Color(0xFFFDF8F8);
      surface               = const Color(0xFFF1EDEC);
      surfaceHigh           = const Color(0xFFEBE7E6);
      surfaceContainerLow   = const Color(0xFFF7F3F2);
      surfaceContainerLowest = const Color(0xFFFFFFFF);
      onSurface             = const Color(0xFF1C1B1B);
      onSurfaceVariant      = const Color(0xFF444748);
      outline               = const Color(0xFF747878);
      outlineVariant        = const Color(0xFFC4C7C7);
      errorContainer        = const Color(0xFFFFDAD6);
    }
  }
}

// ── Text Styles ───────────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // Getters (not fields) so the baked-in colour follows the active theme mode.
  static TextStyle get displayLg => GoogleFonts.playfairDisplay(
    fontSize: 42, fontWeight: FontWeight.w700, height: 1.1,
    letterSpacing: -0.84, color: AppColors.onSurface,
  );
  static TextStyle get displayMd => GoogleFonts.playfairDisplay(
    fontSize: 32, fontWeight: FontWeight.w700, height: 1.2,
    letterSpacing: -0.32, color: AppColors.onSurface,
  );
  static TextStyle get headlineLg => GoogleFonts.playfairDisplay(
    fontSize: 26, fontWeight: FontWeight.w600, height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get headlineMd => GoogleFonts.playfairDisplay(
    fontSize: 22, fontWeight: FontWeight.w600, height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get headlineSm => GoogleFonts.playfairDisplay(
    fontSize: 18, fontWeight: FontWeight.w600, height: 1.3,
    color: AppColors.onSurface,
  );
  static TextStyle get bodyLg => GoogleFonts.inter(
    fontSize: 17, fontWeight: FontWeight.w400, height: 1.6,
    color: AppColors.onSurface,
  );
  static TextStyle get bodyMd => GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w400, height: 1.5,
    color: AppColors.onSurface,
  );
  static TextStyle get bodySm => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400, height: 1.5,
    color: AppColors.onSurfaceVariant,
  );
  static TextStyle get labelCaps => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w700, height: 1.2,
    letterSpacing: 1.2, color: AppColors.onSurfaceVariant,
  );
  static TextStyle get labelMd => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w600, height: 1.2,
    color: AppColors.onSurface,
  );
  static TextStyle get dataLg => GoogleFonts.jetBrainsMono(
    fontSize: 18, fontWeight: FontWeight.w500, height: 1.4,
    color: AppColors.onSurface,
  );
  static TextStyle get dataMd => GoogleFonts.jetBrainsMono(
    fontSize: 14, fontWeight: FontWeight.w500, height: 1.4,
    color: AppColors.onSurface,
  );
  static TextStyle get dataSm => GoogleFonts.jetBrainsMono(
    fontSize: 12, fontWeight: FontWeight.w500, height: 1.4,
    color: AppColors.onSurfaceVariant,
  );
}

// ── Theme ─────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  /// Kept for backwards-compatibility — resolves to the current mode's theme.
  static ThemeData get light => build();

  /// Builds a ThemeData from the current [AppColors] palette. Call after
  /// [AppColors.setDarkMode] so the two stay in sync.
  static ThemeData build() {
    final dark = AppColors.isDark;
    final base = ThemeData(useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light);
    // Nav highlight: primary reads well on white, gold reads well on dark.
    final navSelected = dark ? AppColors.gold : AppColors.primary;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.outline.withValues(alpha: 0.1),
        iconTheme: IconThemeData(color: AppColors.onSurface),
        titleTextStyle: AppTextStyles.headlineSm.copyWith(fontSize: 19),
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: AppTextStyles.labelMd.copyWith(fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.gold),
          textStyle: AppTextStyles.labelMd.copyWith(fontSize: 14, color: AppColors.gold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        labelStyle: AppTextStyles.labelCaps,
        hintStyle: AppTextStyles.bodySm,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        labelStyle: AppTextStyles.bodySm,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        selectedItemColor: navSelected,
        unselectedItemColor: AppColors.onSurfaceVariant,
        selectedLabelStyle: AppTextStyles.bodySm.copyWith(
          fontSize: 11, fontWeight: FontWeight.w600,
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
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: isMobile ? 3 : 5),
          Text(
            label,
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
        return AppColors.statusHigh;
      case 'medium':
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
        flagIcon = Icons.flag_rounded;
        break;
      case 'medium':
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
          Icon(
            flagIcon,
            size: isMobile ? 10 : 12,
            color: c,
          ),
          SizedBox(width: isMobile ? 3 : 4),
          Text(
            priority,
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
  });
  final String title, value;
  final IconData icon;
  final String? sub;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent ? AppColors.primary : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent ? Colors.transparent : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 16,
              color: AppColors.gold,
            ),
            const Spacer(),
            if (sub != null)
              Flexible(
                child: Text(sub!,
                  style: AppTextStyles.bodySm.copyWith(
                    color: accent ? Colors.white54 : null,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
              style: AppTextStyles.dataLg.copyWith(
                fontSize: 22,
                color: accent ? AppColors.gold : AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(title,
            style: AppTextStyles.labelCaps.copyWith(
              fontSize: 9,
              color: accent ? Colors.white60 : AppColors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Section header with optional action
class TSectionHeader extends StatelessWidget {
  const TSectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title, style: AppTextStyles.headlineSm),
      const Spacer(),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(action!,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
          ),
        ),
    ]);
  }
}

/// Avatar with initials
class TAvatar extends StatelessWidget {
  const TAvatar({super.key, required this.name, this.size = 36});
  final String name;
  final double size;
  Color get _bg {
    final colors = [
      const Color(0xFF1A237E), const Color(0xFF4A148C), const Color(0xFF880E4F),
      const Color(0xFF004D40), const Color(0xFF1B5E20), const Color(0xFFE65100),
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
      width: size, height: size,
      decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
      child: Center(
        child: Text(_initials,
          style: AppTextStyles.labelMd.copyWith(
            color: Colors.white,
            fontSize: size * 0.33,
          ),
        ),
      ),
    );
  }
}
