// lib/features/team/department_clients_screen.dart
// Department-scoped Client directory (Team Quick Actions → Clients).
// Clients are linked to a department through client_task_visibility(team_id,
// client_id) — the chosen authoritative link. Admin/manager (of the team) may
// add a client to the active department. All reads/writes are RLS-scoped.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/load_token.dart';
import '../dashboard/dashboard_quick_actions.dart';
import 'team_performance_repository.dart';

class DepartmentClientsScreen extends StatefulWidget {
  const DepartmentClientsScreen({super.key});
  @override
  State<DepartmentClientsScreen> createState() => _DepartmentClientsScreenState();
}

class _DepartmentClientsScreenState extends State<DepartmentClientsScreen> {
  List<TeamMember> _clients = [];
  bool _loading = true;
  bool _adding = false;
  final _loadTok = LoadToken();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? _scopeTeamId() {
    final viewer = context.read<AuthNotifier>().profile;
    final scope = context.read<WorkspaceScopeNotifier>();
    return scope.isGlobal ? scope.taskScopeTeamId : viewer?.teamId;
  }

  Future<void> _load() async {
    final tok = _loadTok.begin();
    final viewer = context.read<AuthNotifier>().profile;
    if (viewer == null) {
      setState(() => _loading = false);
      return;
    }
    final data = await TeamPerformanceRepository.fetchDepartmentClients(
      viewer,
      scopeTeamId: _scopeTeamId(),
    );
    if (mounted && !_loadTok.isStale(tok)) {
      setState(() {
        _clients = data;
        _loading = false;
      });
    }
  }

  Future<void> _addClient() async {
    final teamId = _scopeTeamId();
    if (teamId == null || teamId == WorkspaceScopeState.noTeamSentinel) {
      _snack('Select a department first.', err: true);
      return;
    }
    final all = await TeamPerformanceRepository.fetchAllClients();
    if (!mounted) return;
    final existing = _clients.map((c) => c.id).toSet();
    final options = all.where((c) => !existing.contains(c.id)).toList();
    if (options.isEmpty) {
      _snack('All clients are already in this department.');
      return;
    }
    final picked = await showDialog<TeamMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Add client to department'),
        children: options
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(c.name),
                ))
            .toList(),
      ),
    );
    if (picked == null) return;
    setState(() => _adding = true);
    final err = await TeamPerformanceRepository.addClientToDepartment(teamId, picked.id);
    if (!mounted) return;
    setState(() => _adding = false);
    if (err != null) {
      _snack(err, err: true);
      return;
    }
    _snack('Client added');
    _load();
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red.shade800 : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AuthNotifier, dynamic>((a) => a.profile);
    final allowed = DashboardQuickActions.showTeam(profile); // admin/manager
    final canAdd = profile?.isAdmin == true || profile?.isManager == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: (allowed && canAdd)
          ? FloatingActionButton.extended(
              onPressed: _adding ? null : _addClient,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.person_add_alt, color: AppColors.gold),
              label: const Text('Add client', style: TextStyle(color: AppColors.gold)),
            )
          : null,
      body: !allowed
          ? Center(child: Text('Management only.', style: AppTextStyles.labelMd))
          : _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : _clients.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.business_outlined, size: 56, color: AppColors.outlineVariant),
                          const SizedBox(height: 12),
                          Text('No clients in this department', style: AppTextStyles.labelMd),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.gold,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _clients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _clients[i];
                          return Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.business, color: AppColors.gold),
                              title: Text(c.name, style: AppTextStyles.labelMd),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
