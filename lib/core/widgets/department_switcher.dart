// lib/core/widgets/department_switcher.dart
// Compact in-app department switcher for users authorized to access more than
// one department (admins / super admins). Renders nothing for users who cannot
// switch (managers/employees locked to one department, clients).
//
// Selecting a department updates WorkspaceScopeNotifier and keeps the existing
// admin TeamFilterNotifier in sync, so the current team-filtered screens follow
// the chosen department without each screen needing changes.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/departments.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_controller.dart';
import '../providers/team_filter_notifier.dart';
import '../providers/workspace_scope_notifier.dart';
import '../theme/app_theme.dart';

class DepartmentSwitcher extends StatelessWidget {
  const DepartmentSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    context.select<LocaleController, Locale>((l) => l.locale);
    final scope = context.watch<WorkspaceScopeNotifier>();
    if (!scope.canSwitch) return const SizedBox.shrink();

    final current = scope.effectiveDepartment;
    final label = current?.label ?? S.t('All Departments');

    return PopupMenuButton<Department?>(
      tooltip: S.t('Switch department'),
      onSelected: (dept) => _apply(context, dept),
      itemBuilder: (context) => <PopupMenuEntry<Department?>>[
        PopupMenuItem<Department?>(
          value: null,
          child: _row(S.t('All Departments'), selected: current == null),
        ),
        const PopupMenuDivider(),
        ...scope.authorizedDepartments.map(
          (d) => PopupMenuItem<Department?>(
            value: d,
            child: _row(d.label, selected: current == d),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspaces_outline, size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _apply(BuildContext context, Department? dept) {
    final scope = context.read<WorkspaceScopeNotifier>();
    final ok = scope.select(dept);
    if (!ok) return;

    // Keep the legacy admin team filter aligned with the chosen department so
    // existing team-scoped screens reflect the switch.
    final teamFilter = context.read<TeamFilterNotifier>();
    if (dept == null) {
      teamFilter.clear();
    } else {
      final team = scope.state.teamFor(dept);
      if (team != null) teamFilter.select(team.id);
    }
  }

  Widget _row(String text, {required bool selected}) => Row(
    children: [
      Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 16,
        color: selected ? AppColors.gold : AppColors.onSurfaceVariant,
      ),
      const SizedBox(width: 10),
      Text(text, style: AppTextStyles.bodyMd),
    ],
  );
}
