// lib/core/widgets/bottom_nav_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_notifier.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  // All 5 items in branch order (matches StatefulShellRoute branches 0-4).
  // Built per-frame so labels follow the active language.
  static List<BottomNavigationBarItem> get _allItems => [
    BottomNavigationBarItem(
      icon: const Icon(Icons.dashboard_outlined),
      activeIcon: const Icon(Icons.dashboard),
      label: S.t('dashboard'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.check_box_outlined),
      activeIcon: const Icon(Icons.check_box),
      label: S.t('tasks'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.calendar_month_outlined),
      activeIcon: const Icon(Icons.calendar_month),
      label: S.t('calendar'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.account_balance_wallet_outlined),
      activeIcon: const Icon(Icons.account_balance_wallet),
      label: S.t('finance'),
    ),
    BottomNavigationBarItem(
      icon: const Icon(Icons.settings_outlined),
      activeIcon: const Icon(Icons.settings),
      label: S.t('settings'),
    ),
  ];

  // Branch indices per role (indices map to branches 0-4 in StatefulShellRoute).
  static const _employeeBranchIndices = [0, 1, 2, 4]; // no Finance
  static const _clientBranchIndices = [1, 2, 3, 4]; // no Dashboard

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final isEmployee = profile?.isEmployee ?? false;
    final isClient = profile?.isClient ?? false;

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

    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.outlineVariant, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentVisibleIndex,
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
    );
  }
}
