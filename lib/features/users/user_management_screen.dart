// lib/features/users/user_management_screen.dart
// Team Members screen — checks whether the current user has a team first.
// If no team exists, only a Create Team flow is shown.
// If a team exists, its members are listed with management options.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_privileges_notifier.dart';
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
  bool _pickingTeam = false; // true = admin is on the team-picker screen
  TeamModel? _myTeam;
  List<ProfileModel> _members = [];
  List<ProfileModel> _filtered = [];
  List<TeamModel> _allTeams = [];
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
    // Use postFrameCallback so context.read<AuthNotifier>() is fully ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

    // ── Admin: always show the team-picker first ──────────────────────────
    if (profile.isAdmin) {
      final allTeams = await TeamRepository.fetchAll(activeOnly: true);
      if (mounted) {
        setState(() {
          _allTeams = allTeams;
          _myTeam = null; // clear any previously selected team
          _members = [];
          _filtered = [];
          _pickingTeam = true; // show team-picker, not auto-select
          _loading = false;
        });
        _fadeCtrl.forward(from: 0);
      }
      return;
    }

    // ── Manager / employee: auto-select their assigned team ───────────────
    TeamModel? team;
    final myTeams = await TeamRepository.fetchByLeadId(profile.id);
    if (myTeams.isNotEmpty) {
      team = myTeams.first;
    } else if (profile.teamId != null) {
      final allTeams = await TeamRepository.fetchAll();
      team = allTeams.cast<TeamModel?>().firstWhere(
        (t) => t?.id == profile.teamId,
        orElse: () => null,
      );
    }

    if (team == null) {
      if (mounted) {
        setState(() {
          _myTeam = null;
          _pickingTeam = false;
          _members = [];
          _filtered = [];
          _loading = false;
        });
        _fadeCtrl.forward(from: 0);
      }
      return;
    }

    await _loadTeamMembers(team);
  }

  /// Admin selects a team from the picker.
  Future<void> _selectTeam(TeamModel team) async {
    setState(() => _loading = true);
    await _loadTeamMembers(team);
  }

  Future<void> _loadTeamMembers(TeamModel team) async {
    final members = await TeamRepository.fetchMembers(team.id);
    final allTeams = await TeamRepository.fetchAll(activeOnly: true);
    if (mounted) {
      setState(() {
        _myTeam = team;
        _members = members;
        _filtered = members;
        _allTeams = allTeams;
        _pickingTeam = false;
        _loading = false;
      });
      _filter();
      _fadeCtrl.forward(from: 0);
    }
  }

  /// Admin goes back to the team-picker.
  void _backToTeamPicker() {
    setState(() {
      _myTeam = null;
      _pickingTeam = true;
    });
    _fadeCtrl.forward(from: 0);
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _members
          .where(
            (u) =>
                u.fullName.toLowerCase().contains(q) ||
                u.role.toLowerCase().contains(q),
          )
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.group_add_outlined,
                  color: AppColors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text('Create Your Team', style: AppTextStyles.headlineSm),
            ],
          ),
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

                      final profile = context.read<AuthNotifier>().profile;
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
    final profile = context.watch<AuthNotifier>().profile;
    final privs = context.watch<TeamPrivilegesNotifier>();
    final isAdmin = profile?.isAdmin == true;
    // Admin, a manager with the privilege, or an employee explicitly granted it.
    final canCreateUser = isAdmin || privs.canCreateEmployees;

    // Title & leading button depend on current view
    final String appBarTitle = _pickingTeam
        ? 'Select Team'
        : (_myTeam != null ? _myTeam!.name : 'Team Members');

    final Widget? leading = (!_pickingTeam && _myTeam != null && isAdmin)
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'All Teams',
            onPressed: _backToTeamPicker,
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: leading,
        automaticallyImplyLeading: leading == null,
        title: Text(appBarTitle),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'Create team',
              onPressed: _openCreateTeamDialog,
            ),
          if (!_pickingTeam && _myTeam != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              // Refresh current team's members, not the picker
              onPressed: () => _loadTeamMembers(_myTeam!),
            ),
        ],
      ),
      floatingActionButton: (canCreateUser && !_pickingTeam)
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push(
                  '/create-user',
                  extra: {'teamId': _myTeam?.id, 'teamName': _myTeam?.name},
                );
                // Re-enter load so new user appears
                if (_myTeam != null) {
                  await _loadTeamMembers(_myTeam!);
                } else {
                  _load();
                }
              },
              icon: const Icon(Icons.person_add_outlined),
              label: Text(isAdmin ? 'Create Manager' : 'Create Employee'),
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            )
          : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _pickingTeam
          ? _buildTeamPicker()
          : _myTeam == null
          ? _buildNoTeamState()
          : _buildTeamView(isAdmin),
    );
  }

  // ── Admin: team-picker grid ───────────────────────────────────────────

  Widget _buildTeamPicker() {
    if (_allTeams.isEmpty) {
      // No teams yet — fall through to create-team UI
      return _buildNoTeamState();
    }
    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose a team to manage',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Admin: create a brand-new team.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openCreateTeamDialog,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Create New Team'),
            ),
          ),
          const SizedBox(height: 16),
          ..._allTeams.map(
            (t) => _TeamPickerCard(team: t, onTap: () => _selectTeam(t)),
          ),
          const SizedBox(height: 80),
        ],
      ),
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
                child: const Icon(
                  Icons.group_add_outlined,
                  size: 44,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 24),
              Text('No team yet', style: AppTextStyles.headlineMd),
              const SizedBox(height: 8),
              Text(
                'Create your team first, then start adding members to collaborate on tasks together.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
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

  Widget _buildTeamView(bool isAdmin) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          // Team info banner
          Container(
            width: double.infinity,
            color: AppColors.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
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
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.group_outlined,
                    color: AppColors.gold,
                    size: 20,
                  ),
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
                    // Refresh this team's members only — don't reset to picker
                    if (mounted && _myTeam != null) _loadTeamMembers(_myTeam!);
                  },
                  icon: const Icon(
                    Icons.person_add_outlined,
                    color: AppColors.gold,
                    size: 20,
                  ),
                  tooltip: 'Add Members',
                ),
                // Privileges button — admin only
                if (isAdmin)
                  IconButton(
                    onPressed: () => context.push(
                      '/teams/${_myTeam!.id}/privileges',
                      extra: _myTeam!.name,
                    ),
                    icon: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.onSurfaceVariant,
                      size: 20,
                    ),
                    tooltip: 'Team Privileges',
                  ),
              ],
            ),
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
                        Icon(
                          Icons.person_search_outlined,
                          size: 48,
                          color: AppColors.outlineVariant,
                        ),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _UserCard(
                        user: _filtered[i],
                        teams: _allTeams,
                        onRefresh: _load,
                        isAdmin: isAdmin,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── User Card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.user,
    required this.teams,
    required this.onRefresh,
    required this.isAdmin,
  });
  final ProfileModel user;
  final List<TeamModel> teams;
  final VoidCallback onRefresh;
  final bool isAdmin;

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
    if (mounted)
      setState(() {
        _teamName = name;
        _loadingTeam = false;
      });
  }

  Color get _roleColor {
    switch (widget.user.role) {
      case 'admin':
        return AppColors.primary;
      case 'manager':
        return AppColors.gold;
      case 'employee':
        return AppColors.statusInProgress;
      case 'client':
        return AppColors.statusMedium;
      default:
        return AppColors.onSurfaceVariant;
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
        onSelected: (t) {
          chosen = t;
          Navigator.pop(ctx);
        },
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
      child: Row(
        children: [
          TAvatar(name: u.fullName, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: AppTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TStatusChip(label: u.role, color: _roleColor),
                    TStatusChip(
                      label: u.isActive ? 'Active' : 'Inactive',
                      color: u.isActive
                          ? AppColors.statusDone
                          : AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Team assignment indicator
                Row(
                  children: [
                    Icon(
                      u.teamId != null
                          ? Icons.group_outlined
                          : Icons.group_off_outlined,
                      size: 13,
                      color: u.teamId != null
                          ? AppColors.gold
                          : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    _loadingTeam
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.gold,
                            ),
                          )
                        : Text(
                            u.teamId != null
                                ? (_teamName ?? 'Assigned')
                                : 'Unassigned',
                            style: AppTextStyles.bodySm.copyWith(
                              color: u.teamId != null
                                  ? AppColors.gold
                                  : AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (val) async {
              if (val == 'activate' || val == 'deactivate') {
                final newStatus = val == 'activate' ? 'active' : 'inactive';
                await ProfileRepository.setStatus(u.id, newStatus);
                widget.onRefresh();
              } else if (val == 'assign_team') {
                await _assignTeam();
              } else if (val == 'privileges') {
                context.push(
                  '/users/${u.id}/privileges',
                  extra: {'userName': u.fullName, 'role': u.role},
                );
              } else if (val == 'edit') {
                if (!context.mounted) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _EditEmployeeSheet(
                    user: widget.user,
                    onSaved: widget.onRefresh,
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              if (widget.isAdmin)
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 10),
                      Text('Edit Details'),
                    ],
                  ),
                ),
              // Privileges editable for staff (not clients).
              if (u.role != 'client')
                const PopupMenuItem(
                  value: 'privileges',
                  child: Row(
                    children: [
                      Icon(Icons.tune_outlined, size: 16),
                      SizedBox(width: 10),
                      Text('Edit Privileges'),
                    ],
                  ),
                ),
              if (widget.isAdmin || u.role != 'client')
                const PopupMenuDivider(),
              if (!u.isActive)
                const PopupMenuItem(
                  value: 'activate',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16),
                      SizedBox(width: 10),
                      Text('Activate'),
                    ],
                  ),
                ),
              if (u.isActive)
                const PopupMenuItem(
                  value: 'deactivate',
                  child: Row(
                    children: [
                      Icon(Icons.block_outlined, size: 16),
                      SizedBox(width: 10),
                      Text('Deactivate'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'assign_team',
                child: Row(
                  children: [
                    Icon(Icons.group_outlined, size: 16),
                    SizedBox(width: 10),
                    Text('Assign Team'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Team Picker Card (admin team selector) ────────────────────────────────────

class _TeamPickerCard extends StatelessWidget {
  const _TeamPickerCard({required this.team, required this.onTap});
  final TeamModel team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.group_outlined,
                  color: AppColors.gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: AppTextStyles.labelMd),
                    if (team.department != null &&
                        team.department!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        team.department!,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
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
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('Assign to Team', style: AppTextStyles.headlineSm),
                const Spacer(),
                if (currentTeamId != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(
                      Icons.clear,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Remove',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
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
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final t = teams[i];
                final isCurrent = t.id == currentTeamId;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.group_outlined,
                            size: 18,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: AppTextStyles.labelMd),
                              if (t.department != null &&
                                  t.department!.isNotEmpty)
                                Text(
                                  t.department!,
                                  style: AppTextStyles.bodySm,
                                ),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.gold,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Edit Employee Bottom Sheet ────────────────────────────────────────────────

class _EditEmployeeSheet extends StatefulWidget {
  const _EditEmployeeSheet({required this.user, required this.onSaved});
  final ProfileModel user;
  final VoidCallback onSaved;

  @override
  State<_EditEmployeeSheet> createState() => _EditEmployeeSheetState();
}

class _EditEmployeeSheetState extends State<_EditEmployeeSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loadingEmail = true;
  bool _saving = false;
  bool _obscurePass = true;
  bool _isActive = true;
  String? _selectedRole;
  String? _errorMsg;

  static const _editableRoles = ['employee', 'manager'];

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nameCtrl.text = u.fullName;
    _phoneCtrl.text = u.phone ?? '';
    _isActive = u.isActive;
    _selectedRole = _editableRoles.contains(u.role) ? u.role : u.role;
    _fetchEmail();
  }

  Future<void> _fetchEmail() async {
    final email = await ProfileRepository.fetchEmail(widget.user.id);
    if (mounted) {
      setState(() {
        _emailCtrl.text = email ?? '';
        _loadingEmail = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Full name is required');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Email is required');
      return;
    }
    if (_passCtrl.text.isNotEmpty && _passCtrl.text.length < 8) {
      setState(() => _errorMsg = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final error = await ProfileRepository.updateEmployee(
      userId: widget.user.id,
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      newPassword: _passCtrl.text.isEmpty ? null : _passCtrl.text,
      role: _selectedRole,
      status: _isActive ? 'active' : 'inactive',
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      setState(() => _errorMsg = error);
    } else {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.user.firstName}\'s account updated'),
          backgroundColor: AppColors.statusDone,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminRole = widget.user.isAdmin;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                TAvatar(name: widget.user.fullName, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Edit Account', style: AppTextStyles.headlineSm),
                      Text(
                        widget.user.fullName,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Error banner
            if (_errorMsg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── ACCOUNT ─────────────────────────────────────────────────
            _SheetLabel('ACCOUNT'),
            const SizedBox(height: 10),

            _SheetField(
              controller: _nameCtrl,
              label: 'Full name *',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),

            _loadingEmail
                ? const LinearProgressIndicator(color: AppColors.gold)
                : _SheetField(
                    controller: _emailCtrl,
                    label: 'Email *',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
            const SizedBox(height: 12),

            // Password field
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'New password (leave blank to keep current)',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── PERSONAL ─────────────────────────────────────────────────
            _SheetLabel('PERSONAL'),
            const SizedBox(height: 10),

            _SheetField(
              controller: _phoneCtrl,
              label: 'Phone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),

            // ── ACCESS ───────────────────────────────────────────────────
            _SheetLabel('ACCESS'),
            const SizedBox(height: 10),

            // Role selector (hidden for admin accounts — can't demote admin here)
            if (!isAdminRole) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'ROLE',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'employee', child: Text('Employee')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                ],
                onChanged: (v) => setState(() => _selectedRole = v),
              ),
              const SizedBox(height: 12),
            ],

            // Status toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                title: Text('Account Status', style: AppTextStyles.labelMd),
                subtitle: Text(
                  _isActive
                      ? 'Active — can log in'
                      : 'Inactive — login disabled',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                activeThumbColor: AppColors.gold,
              ),
            ),
            const SizedBox(height: 28),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: AppTextStyles.bodySm.copyWith(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        fontSize: 11,
      ),
    ),
  );
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}
