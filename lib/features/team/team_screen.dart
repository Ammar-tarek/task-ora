// lib/features/team/team_screen.dart
// Team Quick Action — authorized Admin/Manager pick a department employee to
// open their performance hub. Member list is RLS/role scoped.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/profile_model.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/repositories/profile_repository.dart';
import '../../core/services/privileged_ops.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/load_token.dart';
import '../dashboard/dashboard_quick_actions.dart';
import 'deactivation_policy.dart';
import 'team_performance_repository.dart';
import 'employee_performance_screen.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<TeamMember> _members = [];
  bool _loading = true;
  final _loadTok = LoadToken();

  /// Member ids with an in-flight status change — blocks duplicate submits.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Active department team id for the viewer (admin = selected dept; scoped
  /// user = own team). Null = admin in "All Departments".
  String? _scopeTeamId() {
    final viewer = context.read<AuthNotifier>().profile;
    final scope = context.read<WorkspaceScopeNotifier>();
    return scope.isGlobal ? scope.taskScopeTeamId : viewer?.teamId;
  }

  /// Add a regular Employee to the ACTIVE department. Admin only in this
  /// release (the admin-user-ops Edge Function is global-admin-only server
  /// side; a manager patch is prepared but not deployed — see the ticket report).
  Future<void> _addEmployee() async {
    final teamId = _scopeTeamId();
    if (teamId == null || teamId == WorkspaceScopeState.noTeamSentinel) {
      _snack('Open a specific department first.', err: true);
      return;
    }
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Add Employee'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Valid email required' : null,
              ),
              TextFormField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Temp password'),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      // Role is forced to 'employee' here; the server re-validates authorization
      // and the team. Never creates an admin/manager from this flow.
      final id = await PrivilegedOps.createUser(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
        fullName: nameCtrl.text.trim(),
        role: 'employee',
        teamId: teamId,
      );
      if (!mounted) return;
      if (id == null) {
        _snack('Could not create employee (duplicate email or not authorized).', err: true);
        setState(() => _loading = false);
        return;
      }
      _snack('Employee added');
      _load();
    } catch (e) {
      if (mounted) {
        _snack('Create failed: $e', err: true);
        setState(() => _loading = false);
      }
    }
  }

  /// Deactivate (or reactivate) [m] after an explicit confirmation. Admin only;
  /// visibility/eligibility is also gated by [DeactivationPolicy], and the
  /// server re-enforces every rule. Prevents duplicate submits via [_busy].
  Future<void> _toggleActive(TeamMember m) async {
    if (_busy.contains(m.id)) return; // already in-flight
    final deactivating = m.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(
          S.t(deactivating ? 'deactivate_employee_q' : 'reactivate_employee_q'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name, style: AppTextStyles.labelMd),
            const SizedBox(height: 10),
            Text(
              S.t(deactivating ? 'deactivate_warning' : 'reactivate_warning'),
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          ElevatedButton(
            style: deactivating
                ? ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.t(deactivating ? 'deactivate_account' : 'reactivate_account'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy.add(m.id));
    final err = deactivating
        ? await ProfileRepository.deactivateEmployee(m.id)
        : await ProfileRepository.reactivateEmployee(m.id);
    if (!mounted) return;
    setState(() => _busy.remove(m.id));

    if (err != null) {
      _snack(err, err: true);
      return;
    }
    _snack(S.t(deactivating ? 'employee_deactivated' : 'employee_reactivated'));
    // Refresh the member list + any Team Size reading from it.
    await _load();
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red.shade800 : null),
    );
  }

  Future<void> _load() async {
    final tok = _loadTok.begin();
    final viewer = context.read<AuthNotifier>().profile;
    if (viewer == null) {
      setState(() => _loading = false);
      return;
    }
    final members = await TeamPerformanceRepository.fetchMembers(
      viewer,
      scopeTeamId: _scopeTeamId(),
    );
    if (mounted && !_loadTok.isStale(tok)) {
      setState(() {
        _members = members;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AuthNotifier, dynamic>((a) => a.profile);
    final ProfileModel? viewer = profile as ProfileModel?;
    final allowed = DashboardQuickActions.showTeam(profile);

    // Admin only this release (manager create needs an Edge Function patch that
    // is prepared but not deployed). Hidden otherwise.
    final canAddEmployee = profile?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: (allowed && canAddEmployee)
          ? FloatingActionButton.extended(
              onPressed: _addEmployee,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.person_add_alt_1, color: AppColors.gold),
              label: const Text('Add Employee', style: TextStyle(color: AppColors.gold)),
            )
          : null,
      body: !allowed
          ? Center(
              child: Text('Management only.', style: AppTextStyles.labelMd),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : _members.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.groups_outlined, size: 56, color: AppColors.outlineVariant),
                          const SizedBox(height: 12),
                          Text('No team members in your scope', style: AppTextStyles.labelMd),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.gold,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _members.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final inactive = !m.isActive;
                          final busy = _busy.contains(m.id);
                          final canChange = DeactivationPolicy.canChangeStatus(
                            viewer: viewer,
                            targetId: m.id,
                            targetRole: m.role,
                            targetIsSuperAdmin: m.isSuperAdmin,
                          );
                          final tile = Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: ListTile(
                              leading: TAvatar(name: m.name, size: 36),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      m.name,
                                      style: AppTextStyles.labelMd,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (inactive) ...[
                                    const SizedBox(width: 8),
                                    const _InactiveBadge(),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                m.role,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              trailing: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.gold,
                                      ),
                                    )
                                  : canChange
                                      ? PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert,
                                              color: AppColors.gold),
                                          color: AppColors.surfaceContainerLowest,
                                          onSelected: (_) => _toggleActive(m),
                                          itemBuilder: (_) => [
                                            PopupMenuItem<String>(
                                              value: inactive
                                                  ? 'reactivate'
                                                  : 'deactivate',
                                              child: Text(
                                                S.t(inactive
                                                    ? 'reactivate_account'
                                                    : 'deactivate_account'),
                                                style: TextStyle(
                                                  color: inactive
                                                      ? AppColors.onSurface
                                                      : Colors.red.shade400,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Icon(Icons.chevron_right,
                                          color: AppColors.gold),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EmployeePerformanceScreen(member: m),
                                ),
                              ),
                            ),
                          );
                          // Grey out inactive members while keeping them visible.
                          return inactive
                              ? Opacity(opacity: 0.55, child: tile)
                              : tile;
                        },
                      ),
                    ),
    );
  }
}

/// Small "Inactive" pill shown next to a deactivated member's name.
class _InactiveBadge extends StatelessWidget {
  const _InactiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.outlineVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        S.t('inactive'),
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
