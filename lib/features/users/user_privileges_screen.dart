// lib/features/users/user_privileges_screen.dart
// Per-user privileges editor. Admins can open it for anyone; managers for
// members of their own team. Mirrors the admin team-privileges UI but scoped
// to a single person (sub-privileges).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/user_privileges_model.dart';
import '../../core/repositories/user_privileges_repository.dart';
import '../../core/theme/app_theme.dart';

class UserPrivilegesScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? role;

  const UserPrivilegesScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.role,
  });

  @override
  State<UserPrivilegesScreen> createState() => _UserPrivilegesScreenState();
}

class _UserPrivilegesScreenState extends State<UserPrivilegesScreen> {
  bool _loading = true;
  bool _saving  = false;
  UserPrivilegesModel? _privileges;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await UserPrivilegesRepository.fetchForUserOrDefaults(widget.userId);
    if (mounted) setState(() { _privileges = p; _loading = false; });
  }

  Future<void> _toggle(UserPrivilegesModel updated) async {
    final previous = _privileges;
    setState(() { _privileges = updated; _saving = true; });
    try {
      final me = context.read<AuthNotifier>().profile?.id;
      await UserPrivilegesRepository.save(updated, updatedBy: me);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (mounted) {
        setState(() { _privileges = previous; _saving = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Failed to save: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('User Privileges'),
            Text(
              widget.role != null
                  ? '${widget.userName} · ${widget.role}'
                  : widget.userName,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final p = _privileges!;
    final items = [
      _Item(
        icon: Icons.checklist_outlined,
        title: 'Manage Tasks',
        description: 'Create, edit, and assign tasks.',
        value: p.canManageTasks,
        onChanged: (v) => _toggle(p.copyWith(canManageTasks: v)),
      ),
      _Item(
        icon: Icons.access_time_outlined,
        title: 'Manage Attendance',
        description: 'Approve and override attendance records.',
        value: p.canManageAttendance,
        onChanged: (v) => _toggle(p.copyWith(canManageAttendance: v)),
      ),
      _Item(
        icon: Icons.receipt_long_outlined,
        title: 'Manage Expenses',
        description: 'Add, approve, and manage expenses.',
        value: p.canManageExpenses,
        onChanged: (v) => _toggle(p.copyWith(canManageExpenses: v)),
      ),
      _Item(
        icon: Icons.gavel_outlined,
        title: 'Manage Penalties',
        description: 'Issue and track penalty records.',
        value: p.canManagePenalties,
        onChanged: (v) => _toggle(p.copyWith(canManagePenalties: v)),
      ),
      _Item(
        icon: Icons.people_outline,
        title: 'Manage Clients',
        description: 'Create clients and manage invoices.',
        value: p.canManageClients,
        onChanged: (v) => _toggle(p.copyWith(canManageClients: v)),
      ),
      _Item(
        icon: Icons.person_add_outlined,
        title: 'Create Employees',
        description: 'Create new employee accounts for the team.',
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
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppColors.gold, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'These privileges apply to this person specifically and override '
                'the team defaults. Changes save instantly.',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildCard(item),
        )),
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
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: item.value
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(item.icon, size: 18,
            color: item.value ? AppColors.gold : AppColors.onSurfaceVariant),
        ),
        title: Text(item.title, style: AppTextStyles.labelMd),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(item.description,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
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
