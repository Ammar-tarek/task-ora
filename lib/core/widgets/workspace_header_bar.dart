// lib/core/widgets/workspace_header_bar.dart
// Persistent in-app control, shown at the top of every main workspace screen
// (the bottom-nav shell: Dashboard, Tasks, Calendar, Finance, Settings), that
// lets a department-switching user return to the department selection screen.
//
// Visibility: only users authorized to switch departments (admins / super
// admins). Managers, employees and clients never see it, so they stay locked to
// their assigned department. Tapping "Switch" navigates in-app to /workspaces —
// it does NOT sign out, reload the app, or jump to an unrelated dashboard.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/departments.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_controller.dart';
import '../providers/team_filter_notifier.dart';
import '../providers/workspace_scope_notifier.dart';
import '../theme/app_theme.dart';

class WorkspaceHeaderBar extends StatelessWidget {
  const WorkspaceHeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    context.select<LocaleController, Locale>((l) => l.locale);
    final scope = context.watch<WorkspaceScopeNotifier>();

    // Only users who can actually switch departments get the control.
    if (!scope.isGlobal) return const SizedBox.shrink();

    // Label from the live data scope (the selected team) so the header stays
    // consistent with what the screens below are actually showing.
    final teamFilter = context.watch<TeamFilterNotifier>();
    final selectedTeamId = teamFilter.selectedTeamId;
    final department = scope.state.departmentForTeamId(selectedTeamId);
    final label = selectedTeamId == null
        ? S.t('All Departments')
        : (department?.label ??
              teamFilter.selectedTeam?.name ??
              S.t('Department'));

    return Material(
      color: AppColors.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.workspaces_outline, size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Text(
                  '${S.t('Workspace')}: ',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.go('/workspaces'),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(S.t('Switch Department')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: AppTextStyles.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.outlineVariant),
        ],
      ),
    );
  }
}
