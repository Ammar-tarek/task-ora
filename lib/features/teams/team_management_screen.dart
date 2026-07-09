// lib/features/teams/team_management_screen.dart
// Admin-only screen for listing, creating, editing and deleting teams.
// When no teams exist, only the Create Team button is shown — no data is loaded
// in the background. After creating the first team the admin is taken straight
// to the members screen to start adding people.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/team_model.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  List<TeamModel> _teams = [];
  Map<String, int> _memberCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      TeamRepository.fetchAll(),
      TeamRepository.fetchMemberCounts(),
    ]);
    if (mounted) {
      setState(() {
        _teams = results[0] as List<TeamModel>;
        _memberCounts = results[1] as Map<String, int>;
        _loading = false;
      });
    }
  }

  // ── Create / Edit dialog ──────────────────────────────────────────────────

  Future<void> _openTeamDialog({TeamModel? team}) async {
    final nameCtrl = TextEditingController(text: team?.name ?? '');
    final descCtrl = TextEditingController(text: team?.description ?? '');
    final deptCtrl = TextEditingController(text: team?.department ?? '');
    final formKey  = GlobalKey<FormState>();
    bool saving    = false;

    TeamModel? createdTeam;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.group_add_outlined, color: AppColors.gold, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              team == null ? 'Create Team' : 'Edit Team',
              style: AppTextStyles.headlineSm,
            ),
          ]),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'TEAM NAME *',
                      hintText: 'e.g. Engineering',
                      prefixIcon: Icon(Icons.group_outlined, size: 18),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Team name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deptCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'DEPARTMENT',
                      hintText: 'e.g. Product, Sales…',
                      prefixIcon: Icon(Icons.business_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'DESCRIPTION',
                      hintText: 'What does this team do?',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel', style: AppTextStyles.labelMd),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlg(() => saving = true);

                      if (team == null) {
                        final profile =
                            context.read<AuthNotifier>().profile;
                        final created = await TeamRepository.create(
                          name: nameCtrl.text,
                          description: descCtrl.text,
                          department: deptCtrl.text,
                          teamLeadId: profile?.id,
                        );
                        if (created != null) createdTeam = created;
                        if (ctx.mounted) Navigator.pop(ctx);
                      } else {
                        final ok = await TeamRepository.update(
                          id: team.id,
                          name: nameCtrl.text,
                          description: descCtrl.text,
                          department: deptCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to save team')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(team == null ? 'Create & Add Members' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (createdTeam != null) {
      // Refresh team list first, then take admin to the members screen
      await _load();
      if (mounted) {
        await context.push(
          '/teams/${createdTeam!.id}/members',
          extra: createdTeam!.name,
        );
        _load(); // refresh counts on return
      }
    } else {
      _load();
    }
  }

  // ── Delete confirmation ───────────────────────────────────────────────────

  Future<void> _confirmDelete(TeamModel team) async {
    final count = _memberCounts[team.id] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete "${team.name}"?', style: AppTextStyles.headlineSm),
        content: Text(
          count > 0
              ? 'This will unassign $count member${count > 1 ? 's' : ''} and permanently delete the team.'
              : 'This team has no members and will be permanently deleted.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTextStyles.labelMd),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await TeamRepository.delete(team.id);
      if (ok) {
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete team')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTeams = _teams.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          if (hasTeams)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      // FAB only shown when there are existing teams
      floatingActionButton: hasTeams && !_loading
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.gold,
              onPressed: () => _openTeamDialog(),
              icon: const Icon(Icons.add),
              label: Text(
                'New Team',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _teams.isEmpty
              ? _buildFirstTimeEmpty()
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _teams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _TeamCard(
                      team: _teams[i],
                      memberCount: _memberCounts[_teams[i].id] ?? 0,
                      onEdit: () => _openTeamDialog(team: _teams[i]),
                      onDelete: () => _confirmDelete(_teams[i]),
                      onManageMembers: () async {
                        await context.push(
                          '/teams/${_teams[i].id}/members',
                          extra: _teams[i].name,
                        );
                        _load();
                      },
                    ),
                  ),
                ),
    );
  }

  /// Shown when there are no teams at all — just a big centered create button.
  Widget _buildFirstTimeEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Illustration circle
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.15),
                    AppColors.gold.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.group_add_outlined, size: 44, color: AppColors.gold),
            ),
            const SizedBox(height: 24),
            Text('No teams yet', style: AppTextStyles.headlineMd),
            const SizedBox(height: 8),
            Text(
              'Create your first team and start adding members to it.',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openTeamDialog(),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Create Your First Team'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Team Card ─────────────────────────────────────────────────────────────────

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.memberCount,
    required this.onEdit,
    required this.onDelete,
    required this.onManageMembers,
  });

  final TeamModel team;
  final int memberCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageMembers;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: team.isActive
              ? AppColors.outlineVariant
              : AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // ── Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.2),
                      AppColors.gold.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.group_outlined, color: AppColors.gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          team.name,
                          style: AppTextStyles.labelMd,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!team.isActive) ...[ 
                        const SizedBox(width: 6),
                        TStatusChip(label: 'Inactive', color: AppColors.onSurfaceVariant),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Wrap(spacing: 8, children: [
                      if (team.department != null && team.department!.isNotEmpty)
                        _MetaChip(
                          icon: Icons.business_outlined,
                          label: team.department!,
                        ),
                      _MetaChip(
                        icon: Icons.people_outline,
                        label: '$memberCount member${memberCount != 1 ? 's' : ''}',
                      ),
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 10),
                      Text('Edit Team'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'members',
                    child: Row(children: [
                      Icon(Icons.manage_accounts_outlined, size: 16),
                      SizedBox(width: 10),
                      Text('Manage Members'),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'members') onManageMembers();
                  if (val == 'delete') onDelete();
                },
              ),
            ]),
          ),

          // ── Description
          if (team.description != null && team.description!.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                Icon(Icons.notes_outlined, size: 14, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    team.description!,
                    style: AppTextStyles.bodySm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ],

          // ── Manage Members footer
          const Divider(height: 1),
          InkWell(
            onTap: onManageMembers,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.manage_accounts_outlined, size: 16, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Text(
                    'Manage Members',
                    style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small meta chip ───────────────────────────────────────────────────────────
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label, style: AppTextStyles.bodySm.copyWith(fontSize: 12)),
        ],
      );
}
