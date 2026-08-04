// lib/core/widgets/bottom_nav_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_notifier.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_controller.dart';
import '../providers/theme_controller.dart';
import '../theme/app_theme.dart';

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  // All 5 items in branch order (matches StatefulShellRoute branches 0-4).
  // Built per-frame so labels follow the active language.
  static List<BottomNavigationBarItem> get _allItems => [
    BottomNavigationBarItem(
      icon: const Icon(Icons.dashboard_outlined),
      activeIcon: const Icon(Icons.dashboard_rounded),
      label: S.t('dashboard'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.check_box_outlined),
      activeIcon: const Icon(Icons.check_box_rounded),
      label: S.t('tasks'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.calendar_month_outlined),
      activeIcon: const Icon(Icons.calendar_month_rounded),
      label: S.t('calendar'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.account_balance_wallet_outlined),
      activeIcon: const Icon(Icons.account_balance_wallet_rounded),
      label: S.t('finance'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.settings_outlined),
      activeIcon: const Icon(Icons.settings_rounded),
      label: S.t('settings'),
    ),
  ];

  // Branch indices per role (indices map to branches 0-4 in StatefulShellRoute).
  static const _employeeBranchIndices = [0, 1, 2, 4]; // no Finance
  static const _clientBranchIndices = [1, 2, 3, 4]; // no Dashboard

  @override
  Widget build(BuildContext context) {
    context.select<ThemeController, bool>((t) => t.isDark);
    context.select<LocaleController, Locale>((l) => l.locale);
    final profile = context.select<AuthNotifier, dynamic>((a) => a.profile);
    final isEmployee = profile?.isEmployee ?? false;
    final isClient = profile?.isClient ?? false;
    final isDark = AppColors.isDark;

    // Build the visible item list and a mapping: visible-index → branch-index.
    final List<BottomNavigationBarItem> visibleItems;
    final List<int> branchIndices;

    if (isEmployee) {
      branchIndices = _employeeBranchIndices;
      visibleItems = branchIndices.map((i) => _allItems[i]).toList();
    } else if (isClient) {
      branchIndices = _clientBranchIndices;
      visibleItems = branchIndices.map((i) => _allItems[i]).toList();
    } else {
      branchIndices = List.generate(_allItems.length, (i) => i);
      visibleItems = _allItems.toList();
    }

    // Map the shell's current branch index → visible bar index.
    final currentBranchIndex = shell.currentIndex;
    int currentVisibleIndex = branchIndices.indexOf(currentBranchIndex);
    if (currentVisibleIndex == -1) currentVisibleIndex = 0;

    final activeColor = isDark ? AppColors.gold : AppColors.primary;
    final inactiveColor = AppColors.onSurfaceVariant.withValues(alpha: 0.7);

    return Scaffold(
      body: shell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: RepaintBoundary(
          child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark 
                  ? AppColors.gold.withValues(alpha: 0.25)
                  : AppColors.outlineVariant,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                currentIndex: currentVisibleIndex,
                elevation: 0,
                backgroundColor: Colors.transparent,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: activeColor,
                unselectedItemColor: inactiveColor,
                selectedFontSize: 12,
                unselectedFontSize: 11,
                selectedLabelStyle: AppTextStyles.labelMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: activeColor,
                ),
                unselectedLabelStyle: AppTextStyles.bodySm.copyWith(
                  fontSize: 11,
                  color: inactiveColor,
                ),
                onTap: (visibleIndex) {
                  final branchIndex = branchIndices[visibleIndex];
                  shell.goBranch(
                    branchIndex,
                    initialLocation: branchIndex == shell.currentIndex,
                  );
                },
                items: visibleItems,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}

