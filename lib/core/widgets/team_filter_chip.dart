// lib/core/widgets/team_filter_chip.dart
// Compact "All Teams | Team A | Team B" dropdown shown at the top of
// admin-facing screens. Only renders when the profile is admin.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_notifier.dart';
import '../providers/team_filter_notifier.dart';
import '../theme/app_theme.dart';

class TeamFilterChip extends StatelessWidget {
  const TeamFilterChip({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    if (profile?.isAdmin != true) return const SizedBox.shrink();

    final filter = context.watch<TeamFilterNotifier>();
    final teams  = filter.teams;

    if (teams.isEmpty) {
      // Trigger load if not yet done
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<TeamFilterNotifier>().loadTeams();
      });
      return const SizedBox.shrink();
    }

    final selectedId   = filter.selectedTeamId;
    final selectedName = filter.selectedTeam?.name ?? 'All Teams';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          Icon(Icons.filter_list_outlined,
              size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Team:', style: AppTextStyles.bodySm),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    context: context,
                    label: 'All',
                    selected: selectedId == null,
                    onTap: () => context.read<TeamFilterNotifier>().clear(),
                  ),
                  ...teams.map((t) => _chip(
                        context: context,
                        label: t.name,
                        selected: selectedId == t.id,
                        onTap: () =>
                            context.read<TeamFilterNotifier>().select(t.id),
                      )),
                ],
              ),
            ),
          ),
          if (selectedId != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '· $selectedName',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.gold, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.6)
                : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            color: selected ? AppColors.gold : AppColors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
