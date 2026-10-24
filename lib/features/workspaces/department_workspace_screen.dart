// lib/features/workspaces/department_workspace_screen.dart
// Department workspace entry / selection screen (M2).
//
// - Admins: a polished picker of all department workspaces + company Expenses.
// - Super Admins: the same, plus a "Company Overview" banner (global access).
//   NOTE: the super-admin distinction is currently navigation-only — it is NOT
//   a security boundary until the DB `is_super_admin` column + RLS land (M8).
// - Managers/Employees never reach this screen (the router guard redirects them
//   to their authorized workspace); Clients keep the client-facing workspace.
//
// Styled with the agreed Dark Premium tokens as a contained preview of the new
// direction — the full theme migration is a later milestone.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/constants/departments.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/dark_premium.dart';
import '../../core/widgets/department_switcher.dart';

class DepartmentWorkspaceScreen extends StatelessWidget {
  const DepartmentWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.select<LocaleController, Locale>((l) => l.locale);
    final profile = context.select<AuthNotifier, dynamic>((a) => a.profile);
    final scope = context.watch<WorkspaceScopeNotifier>();
    final departments = scope.authorizedDepartments;
    final isSuperAdmin = profile?.isSuperAdmin == true;

    return Theme(
      // Local Dark Premium preview — does not alter the global theme.
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: DarkPremium.background,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: DarkPremium.background,
        appBar: AppBar(
          backgroundColor: DarkPremium.background,
          elevation: 0,
          title: Text(
            S.t('Workspaces'),
            style: AppTextStyles.headlineSm.copyWith(color: Colors.white),
          ),
          actions: const [DepartmentSwitcher(), SizedBox(width: 8)],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                S.t('Select a workspace'),
                style: AppTextStyles.bodySm.copyWith(
                  color: Colors.white70,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              if (isSuperAdmin) ...[
                _CompanyOverviewBanner(departmentCount: departments.length),
                const SizedBox(height: 20),
              ],
              _WorkspaceGrid(
                children: [
                  for (final d in departments)
                    _WorkspaceCard(
                      label: S.t(d.label),
                      icon: _iconFor(d),
                      onTap: () => _enterDepartment(context, d),
                    ),
                  if (scope.canAccessExpenses)
                    _WorkspaceCard(
                      label: S.t('Company Expenses'),
                      icon: Icons.account_balance_wallet_outlined,
                      subtitle: S.t('Company-wide'),
                      onTap: () => context.go('/expenses'),
                    ),
                ],
              ),
              if (departments.isEmpty && !scope.canAccessExpenses) ...[
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    S.t('No workspace is assigned to your account yet.'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd.copyWith(color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _enterDepartment(BuildContext context, Department department) {
    final scope = context.read<WorkspaceScopeNotifier>();
    if (scope.select(department)) {
      final team = scope.state.teamFor(department);
      if (team != null) {
        context.read<TeamFilterNotifier>().select(team.id);
      }
    }
    context.go('/dashboard');
  }

  static IconData _iconFor(Department d) {
    switch (d) {
      case Department.marketing:
        return Icons.campaign_outlined;
      case Department.montage:
        return Icons.content_cut_outlined;
      case Department.production:
        return Icons.videocam_outlined;
      case Department.sales:
        return Icons.trending_up_outlined;
      case Department.studio:
        return Icons.palette_outlined;
    }
  }
}

class _CompanyOverviewBanner extends StatelessWidget {
  const _CompanyOverviewBanner({required this.departmentCount});
  final int departmentCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DarkPremium.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DarkPremium.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: DarkPremium.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_moon_outlined,
              color: DarkPremium.onAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('Company Overview'),
                  style: AppTextStyles.headlineSm.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${S.t('Global access')} · $departmentCount ${S.t('departments')}',
                  style: AppTextStyles.bodySm.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceGrid extends StatelessWidget {
  const _WorkspaceGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 900 ? 3 : (width >= 560 ? 2 : 1);
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.9,
      children: children,
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DarkPremium.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DarkPremium.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DarkPremium.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: DarkPremium.accent, size: 22),
              ),
              const Spacer(),
              Text(
                label,
                style: AppTextStyles.headlineSm.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: AppTextStyles.bodySm.copyWith(color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
