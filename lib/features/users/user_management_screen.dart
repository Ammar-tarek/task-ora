// lib/features/users/user_management_screen.dart
// Team Members screen — checks whether the current user has a team first.
// If no team exists, only a Create Team flow is shown.
// If a team exists, its members are listed with management options.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/profile_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/models/profile_model.dart';
import '../../core/models/team_model.dart';
import '../../core/theme/app_theme.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  bool _loading = true;
  TeamModel? _myTeam;          // null → user hasn't created a team yet
  List<ProfileModel> _members = [];
  List<ProfileModel> _filtered = [];
  List<TeamModel> _allTeams = []; // for team picker (admin may have multiple)
  final _search = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _search.addListener(_filter);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _load({bool animate = true}) async {
    if (animate) setState(() => _loading = true);

    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Step 1: Check if this user leads any team
    final myTeams = await TeamRepository.fetchByLeadId(profile.id);

    // Also check if the user is simply assigned to a team (for non-admin
    // users who might reach this screen in the future)
    TeamModel? team;
    if (myTeams.isNotEmpty) {
      team = myTeams.first; // use the first team they lead
    } else if (profile.teamId != null) {
      // User has a team_id but isn't the lead — try to look it up
      final allTeams = await TeamRepository.fetchAll();
      team = allTeams.cast<TeamModel?>().firstWhere(
        (t) => t?.id == profile.teamId,
        orElse: () => null,
      );
    }

    if (team == null) {
      // ── No team at all → show create-team UI
      if (mounted) {
        setState(() {
          _myTeam = null;
          _members = [];
          _filtered = [];
          _loading = false;
        });
        _fadeCtrl.forward(from: 0);
      }
      return;
    }

    // Step 2: Team exists → fetch its members only
    final members = await TeamRepository.fetchMembers(team.id);
    final allTeams = await TeamRepository.fetchAll(activeOnly: true);

    if (mounted) {
      setState(() {
        _myTeam = team;
        _members = members;
        _filtered = members;
        _allTeams = allTeams;
        _loading = false;
      });
      _filter();
      _fadeCtrl.forward(from: 0);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _members
          .where((u) =>
              u.fullName.toLowerCase().contains(q) ||
              u.role.toLowerCase().contains(q))
          .toList();
    });
  }

  // ── Create Team dialog ─────────────────────────────────────────────────

  Future<void> _openCreateTeamDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    TeamModel? createdTeam;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.group_add_outlined,
                  color: AppColors.gold, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Create Your Team', style: AppTextStyles.headlineSm),
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
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Team name is required'
                        : null,
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
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create Team'),
            ),
          ],
        ),
      ),
    );

    if (createdTeam != null) {
      _load(); // Reload — team now exists, will show members list
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_myTeam != null ? _myTeam!.name : 'Team Members'),
        actions: [
          if (_myTeam != null)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _myTeam == null
              ? _buildNoTeamState()
              : _buildTeamView(),
    );
  }

  // ── No-team empty state ──────────────────────────────────────────────

  Widget _buildNoTeamState() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Illustration circle
              Container(
                width: 96,
                height: 96,
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
                child: const Icon(Icons.group_add_outlined,
                    size: 44, color: AppColors.gold),
              ),
              const SizedBox(height: 24),
              Text('No team yet', style: AppTextStyles.headlineMd),
              const SizedBox(height: 8),
              Text(
                'Create your team first, then start adding members to collaborate on tasks together.',
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openCreateTeamDialog,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Create Your Team'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Team exists → show members ────────────────────────────────────────

  Widget _buildTeamView() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(children: [
        // Team info banner
        Container(
          width: double.infinity,
          color: AppColors.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
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
                border:
                    Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.group_outlined,
                  color: AppColors.gold, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_myTeam!.name, style: AppTextStyles.labelMd),
                  const SizedBox(height: 2),
                  Text(
                    '${_members.length} member${_members.length != 1 ? 's' : ''}'
                    '${_myTeam!.department != null && _myTeam!.department!.isNotEmpty ? ' · ${_myTeam!.department}' : ''}',
                    style: AppTextStyles.bodySm,
                  ),
                ],
              ),
            ),
            // Manage members button → go to the dedicated members screen
            IconButton(
              onPressed: () async {
                await context.push(
                  '/teams/${_myTeam!.id}/members',
                  extra: _myTeam!.name,
                );
                _load(); // refresh on return
              },
              icon: const Icon(Icons.person_add_outlined,
                  color: AppColors.gold, size: 20),
              tooltip: 'Add Members',
            ),
          ]),
        ),
        const Divider(height: 1),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search by name or role…',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),

        // Members list
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_search_outlined,
                          size: 48, color: AppColors.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        _search.text.isNotEmpty
                            ? 'No matching members'
                            : 'No members yet',
                        style: AppTextStyles.labelMd,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _search.text.isNotEmpty
                            ? 'Try a different search term'
                            : 'Tap + above to add members to your team',
                        style: AppTextStyles.bodySm,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _UserCard(
                      user: _filtered[i],
                      teams: _allTeams,
                      onRefresh: _load,
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ── User Card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.user,
    required this.teams,
    required this.onRefresh,
  });
  final ProfileModel user;
  final List<TeamModel> teams;
  final VoidCallback onRefresh;

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  String? _teamName;
  bool _loadingTeam = false;

  @override
  void initState() {
    super.initState();
    _fetchTeamName();
  }

  Future<void> _fetchTeamName() async {
    if (widget.user.teamId == null) return;
    setState(() => _loadingTeam = true);
    final name = await ProfileRepository.fetchTeamName(widget.user.teamId);
    if (mounted) setState(() { _teamName = name; _loadingTeam = false; });
  }

  Color get _roleColor {
    switch (widget.user.role) {
      case 'admin':    return AppColors.primary;
      case 'employee': return AppColors.statusInProgress;
      case 'client':   return AppColors.statusMedium;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  Future<void> _assignTeam() async {
    TeamModel? chosen;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _TeamPickerSheet(
        teams: widget.teams,
        currentTeamId: widget.user.teamId,
        onSelected: (t) { chosen = t; Navigator.pop(ctx); },
        onClear: () async {
          await TeamRepository.setTeamForUser(widget.user.id, null);
          widget.onRefresh();
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );

    if (chosen != null) {
      await TeamRepository.setTeamForUser(widget.user.id, chosen!.id);
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        TAvatar(name: u.fullName, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.fullName, style: AppTextStyles.labelMd,
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              TStatusChip(label: u.role, color: _roleColor),
              TStatusChip(
                label: u.isActive ? 'Active' : 'Inactive',
                color: u.isActive ? AppColors.statusDone : AppColors.onSurfaceVariant,
              ),
            ]),
            const SizedBox(height: 4),
            // Team assignment indicator
            Row(children: [
              Icon(
                u.teamId != null ? Icons.group_outlined : Icons.group_off_outlined,
                size: 13,
                color: u.teamId != null ? AppColors.gold : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              _loadingTeam
                  ? const SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold),
                    )
                  : Text(
                      u.teamId != null
                          ? (_teamName ?? 'Assigned')
                          : 'Unassigned',
                      style: AppTextStyles.bodySm.copyWith(
                        color: u.teamId != null ? AppColors.gold : AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: (val) async {
            if (val == 'activate' || val == 'deactivate') {
              final newStatus = val == 'activate' ? 'active' : 'inactive';
              await ProfileRepository.setStatus(u.id, newStatus);
              widget.onRefresh();
            } else if (val == 'assign_team') {
              await _assignTeam();
            }
          },
          itemBuilder: (_) => [
            if (!u.isActive)
              const PopupMenuItem(
                value: 'activate',
                child: Row(children: [
                  Icon(Icons.check_circle_outline, size: 16),
                  SizedBox(width: 10),
                  Text('Activate'),
                ]),
              ),
            if (u.isActive)
              const PopupMenuItem(
                value: 'deactivate',
                child: Row(children: [
                  Icon(Icons.block_outlined, size: 16),
                  SizedBox(width: 10),
                  Text('Deactivate'),
                ]),
              ),
            const PopupMenuItem(
              value: 'assign_team',
              child: Row(children: [
                Icon(Icons.group_outlined, size: 16),
                SizedBox(width: 10),
                Text('Assign Team'),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

// ── Team Picker Bottom Sheet ──────────────────────────────────────────────────

class _TeamPickerSheet extends StatelessWidget {
  const _TeamPickerSheet({
    required this.teams,
    required this.currentTeamId,
    required this.onSelected,
    required this.onClear,
  });
  final List<TeamModel> teams;
  final String? currentTeamId;
  final void Function(TeamModel) onSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(children: [
            Text('Assign to Team', style: AppTextStyles.headlineSm),
            const Spacer(),
            if (currentTeamId != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 16, color: AppColors.error),
                label: Text('Remove',
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.error)),
              ),
          ]),
        ),
        if (teams.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No active teams found', style: AppTextStyles.bodySm),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            itemCount: teams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final t = teams[i];
              final isCurrent = t.id == currentTeamId;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.gold.withValues(alpha: 0.08)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.gold.withValues(alpha: 0.5)
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.group_outlined,
                          size: 18, color: AppColors.gold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, style: AppTextStyles.labelMd),
                          if (t.department != null && t.department!.isNotEmpty)
                            Text(t.department!, style: AppTextStyles.bodySm),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      const Icon(Icons.check_circle,
                          color: AppColors.gold, size: 20),
                  ]),
                ),
              );
            },
          ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
