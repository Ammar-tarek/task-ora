// lib/features/teams/team_privileges_screen.dart
// Admin UI to configure which features a team's manager can access.

import 'package:flutter/material.dart';
import '../../core/models/team_privileges_model.dart';
import '../../core/repositories/team_privileges_repository.dart';
import '../../core/theme/app_theme.dart';

class TeamPrivilegesScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const TeamPrivilegesScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamPrivilegesScreen> createState() => _TeamPrivilegesScreenState();
}

class _TeamPrivilegesScreenState extends State<TeamPrivilegesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _setupRequired = false; // true when team_privileges table is missing
  TeamPrivilegesModel? _privileges;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _setupRequired = false;
    });
    try {
      final p = await TeamPrivilegesRepository.fetchForTeam(widget.teamId);
      if (mounted)
        setState(() {
          _privileges = p;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _setupRequired = true;
        });
    }
  }

  Future<void> _toggle(TeamPrivilegesModel updated) async {
    final previous = _privileges;
    setState(() {
      _privileges = updated;
      _saving = true;
    });
    try {
      await TeamPrivilegesRepository.save(updated);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      // Revert optimistic update and show error
      if (mounted) {
        setState(() {
          _privileges = previous;
          _saving = false;
        });
        _showSaveError(e);
      }
    }
  }

  void _showSaveError(Object e) {
    final msg = e.toString();
    // PGRST205 = PostgREST can't find table in schema cache (table doesn't exist)
    // 42P01    = PostgreSQL undefined_table
    final isMissing =
        msg.contains('PGRST205') ||
        msg.contains('schema cache') ||
        msg.contains('team_privileges') ||
        msg.contains('does not exist') ||
        msg.contains('42P01');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 6),
        content: Text(
          isMissing
              ? 'Table not found. Run the SQL migration in Supabase first.'
              : 'Failed to save: $msg',
        ),
        action: isMissing
            ? SnackBarAction(
                label: 'SQL',
                textColor: AppColors.gold,
                onPressed: _showMigrationDialog,
              )
            : null,
      ),
    );
  }

  void _showMigrationDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('SQL Migration Required'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'Run this in your Supabase SQL Editor:\n\n'
            'CREATE TABLE IF NOT EXISTS public.team_privileges (\n'
            '  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),\n'
            '  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,\n'
            '  can_manage_attendance BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_manage_expenses   BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_manage_tasks      BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_manage_penalties  BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_manage_clients    BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_create_employees  BOOLEAN NOT NULL DEFAULT true,\n'
            '  can_view_finance      BOOLEAN NOT NULL DEFAULT false,\n'
            '  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),\n'
            '  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),\n'
            '  UNIQUE (team_id)\n'
            ');\n'
            'ALTER TABLE public.team_privileges ENABLE ROW LEVEL SECURITY;\n'
            'CREATE POLICY "admin_all" ON public.team_privileges\n'
            '  FOR ALL TO authenticated\n'
            '  USING (EXISTS (SELECT 1 FROM public.profiles\n'
            '    WHERE id = auth.uid() AND role = \'admin\'));\n'
            'CREATE POLICY "manager_read_own" ON public.team_privileges\n'
            '  FOR SELECT TO authenticated\n'
            '  USING (EXISTS (SELECT 1 FROM public.profiles\n'
            '    WHERE id = auth.uid() AND role = \'manager\'\n'
            '    AND team_id = team_privileges.team_id));',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Team Privileges'),
            Text(
              widget.teamName,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _setupRequired
          ? _buildSetupRequired()
          : _buildBody(),
    );
  }

  Widget _buildSetupRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.build_circle_outlined,
              size: 64,
              color: AppColors.gold,
            ),
            const SizedBox(height: 16),
            Text('Database setup required', style: AppTextStyles.headlineSm),
            const SizedBox(height: 8),
            Text(
              'The team_privileges table does not exist yet.\n'
              'Run the SQL migration in your Supabase SQL Editor.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showMigrationDialog,
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text('View SQL'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _load,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  label: const Text(
                    'Retry',
                    style: TextStyle(color: AppColors.gold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final p = _privileges!;

    final items = [
      _Item(
        icon: Icons.checklist_outlined,
        title: 'Manage Tasks',
        description: 'Create, edit, and assign tasks to team members.',
        value: p.canManageTasks,
        onChanged: (v) => _toggle(p.copyWith(canManageTasks: v)),
      ),
      _Item(
        icon: Icons.access_time_outlined,
        title: 'Manage Attendance',
        description: 'Record and view attendance logs for the team.',
        value: p.canManageAttendance,
        onChanged: (v) => _toggle(p.copyWith(canManageAttendance: v)),
      ),
      _Item(
        icon: Icons.receipt_long_outlined,
        title: 'Manage Expenses',
        description: 'Approve or reject expense requests from employees.',
        value: p.canManageExpenses,
        onChanged: (v) => _toggle(p.copyWith(canManageExpenses: v)),
      ),
      _Item(
        icon: Icons.gavel_outlined,
        title: 'Manage Penalties',
        description: 'Issue and track penalty records for team members.',
        value: p.canManagePenalties,
        onChanged: (v) => _toggle(p.copyWith(canManagePenalties: v)),
      ),
      _Item(
        icon: Icons.people_outline,
        title: 'Manage Clients',
        description: 'Create clients and manage invoices for the team.',
        value: p.canManageClients,
        onChanged: (v) => _toggle(p.copyWith(canManageClients: v)),
      ),
      _Item(
        icon: Icons.person_add_outlined,
        title: 'Create Employees',
        description:
            'Create new employee accounts and assign them to this team.',
        value: p.canCreateEmployees,
        onChanged: (v) => _toggle(p.copyWith(canCreateEmployees: v)),
      ),
      _Item(
        icon: Icons.account_balance_outlined,
        title: 'View Finance',
        description: 'Access the finance dashboard and analytics.',
        value: p.canViewFinance,
        onChanged: (v) => _toggle(p.copyWith(canViewFinance: v)),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.gold, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Changes save instantly. The manager will see updated permissions on their next action.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCard(item),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(_Item item) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.value
              ? AppColors.gold.withValues(alpha: 0.35)
              : AppColors.outlineVariant,
        ),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: item.value
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item.icon,
            size: 18,
            color: item.value ? AppColors.gold : AppColors.onSurfaceVariant,
          ),
        ),
        title: Text(item.title, style: AppTextStyles.labelMd),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            item.description,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        value: item.value,
        onChanged: _saving ? null : item.onChanged,
        activeThumbColor: AppColors.gold,
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Item({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });
}
