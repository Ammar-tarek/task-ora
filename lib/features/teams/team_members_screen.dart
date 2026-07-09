// lib/features/teams/team_members_screen.dart
// Admin screen: view current members of a team and add new members by email.
// No user data is fetched until the admin types and searches a valid email.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/profile_model.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../../core/theme/app_theme.dart';

class TeamMembersScreen extends StatefulWidget {
  const TeamMembersScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  final String teamId;
  final String teamName;

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  // ── Members list
  List<ProfileModel> _members = [];
  bool _loadingMembers = true;

  // ── Email search state
  final _emailCtrl = TextEditingController();
  bool _emailValid = false;
  bool _searching = false;
  ProfileModel? _foundUser;
  String? _searchMessage; // null = no search yet, 'not_found', 'already_member', 'other_team'
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _emailCtrl.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ── Email validation ──────────────────────────────────────────────────────

  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');

  void _onEmailChanged() {
    final valid = _emailRegex.hasMatch(_emailCtrl.text.trim());
    setState(() {
      _emailValid = valid;
      // Reset result whenever the user edits the email
      if (_foundUser != null || _searchMessage != null) {
        _foundUser = null;
        _searchMessage = null;
      }
    });
  }

  // ── Load existing members ─────────────────────────────────────────────────

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    final members = await TeamRepository.fetchMembers(widget.teamId);
    if (mounted) {
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    }
  }

  // ── Search by email ───────────────────────────────────────────────────────

  Future<void> _searchByEmail() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _foundUser = null;
      _searchMessage = null;
    });

    final profile = await ProfileRepository.fetchByEmail(_emailCtrl.text.trim());

    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _searching = false;
        _searchMessage = 'not_found';
      });
      return;
    }

    // Already a member of THIS team?
    if (_members.any((m) => m.id == profile.id)) {
      setState(() {
        _searching = false;
        _foundUser = profile;
        _searchMessage = 'already_member';
      });
      return;
    }

    setState(() {
      _searching = false;
      _foundUser = profile;
      _searchMessage = profile.teamId != null ? 'other_team' : null;
    });
  }

  // ── Add found user ────────────────────────────────────────────────────────

  Future<void> _addFoundUser() async {
    if (_foundUser == null) return;
    setState(() => _adding = true);
    final ok = await TeamRepository.setTeamForUser(_foundUser!.id, widget.teamId);
    if (!mounted) return;
    if (ok) {
      // Clear search & refresh list
      _emailCtrl.clear();
      setState(() {
        _foundUser = null;
        _searchMessage = null;
        _emailValid = false;
        _adding = false;
      });
      _loadMembers();
    } else {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add member. Please try again.')),
      );
    }
  }

  // ── Remove member ─────────────────────────────────────────────────────────

  Future<void> _removeMember(ProfileModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Remove ${user.firstName}?', style: AppTextStyles.headlineSm),
        content: Text(
          '${user.fullName} will be unassigned from "${widget.teamName}".',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await TeamRepository.setTeamForUser(user.id, null);
      _loadMembers();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.teamName),
            if (!_loadingMembers)
              Text(
                '${_members.length} member${_members.length != 1 ? 's' : ''}',
                style: AppTextStyles.bodySm,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMembers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Email Search Section ─────────────────────────────────────────
          _EmailSearchPanel(
            emailCtrl: _emailCtrl,
            emailValid: _emailValid,
            searching: _searching,
            adding: _adding,
            foundUser: _foundUser,
            searchMessage: _searchMessage,
            onSearch: _emailValid && !_searching ? _searchByEmail : null,
            onAdd: (_foundUser != null &&
                    _searchMessage != 'already_member' &&
                    !_adding)
                ? _addFoundUser
                : null,
          ),

          // ── Divider between search and list
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Divider(height: 1),
          ),

          // ── Members label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              Icon(Icons.people_outline, size: 16, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Current Members', style: AppTextStyles.labelMd),
            ]),
          ),

          // ── Members list
          Expanded(
            child: _loadingMembers
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : _members.isEmpty
                    ? _buildEmptyMembers()
                    : RefreshIndicator(
                        color: AppColors.gold,
                        onRefresh: _loadMembers,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _members.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _MemberCard(
                            user: _members[i],
                            onRemove: () => _removeMember(_members[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyMembers() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 48,
              color: AppColors.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text('No members yet', style: AppTextStyles.labelMd),
            const SizedBox(height: 4),
            Text(
              'Search by email above to add members.',
              style: AppTextStyles.bodySm,
            ),
          ],
        ),
      );
}

// ── Email Search Panel ────────────────────────────────────────────────────────

class _EmailSearchPanel extends StatelessWidget {
  const _EmailSearchPanel({
    required this.emailCtrl,
    required this.emailValid,
    required this.searching,
    required this.adding,
    required this.foundUser,
    required this.searchMessage,
    required this.onSearch,
    required this.onAdd,
  });

  final TextEditingController emailCtrl;
  final bool emailValid;
  final bool searching;
  final bool adding;
  final ProfileModel? foundUser;
  final String? searchMessage;
  final VoidCallback? onSearch;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Member by Email', style: AppTextStyles.labelMd),
          const SizedBox(height: 10),

          // ── Email field + Search button
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'user@example.com',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  suffixIcon: emailCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => emailCtrl.clear(),
                        )
                      : null,
                ),
                onSubmitted: (_) => onSearch?.call(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: onSearch,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  backgroundColor: emailValid ? AppColors.primary : AppColors.outlineVariant,
                ),
                child: searching
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, color: Colors.white, size: 20),
              ),
            ),
          ]),

          // ── Validation hint
          if (!emailValid && emailCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(children: [
                Icon(Icons.info_outline, size: 13, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Enter a valid email address (e.g. name@company.com)',
                  style: AppTextStyles.bodySm.copyWith(fontSize: 11),
                ),
              ]),
            ),

          // ── Search result
          if (searchMessage != null || foundUser != null) ...[
            const SizedBox(height: 12),
            _SearchResult(
              user: foundUser,
              message: searchMessage,
              adding: adding,
              onAdd: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Search Result Widget ──────────────────────────────────────────────────────

class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.user,
    required this.message,
    required this.adding,
    required this.onAdd,
  });

  final ProfileModel? user;
  final String? message;
  final bool adding;
  final VoidCallback? onAdd;

  Color get _roleColor {
    switch (user?.role) {
      case 'admin':    return AppColors.primary;
      case 'manager':  return AppColors.gold;
      case 'employee': return AppColors.statusInProgress;
      case 'client':   return AppColors.statusMedium;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Not found
    if (message == 'not_found') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.person_off_outlined, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No account found',
                    style: AppTextStyles.labelMd.copyWith(color: AppColors.error)),
                const SizedBox(height: 2),
                Text(
                  'No user is registered with this email. Check the address and try again.',
                  style: AppTextStyles.bodySm,
                ),
              ],
            ),
          ),
        ]),
      );
    }

    // Already a member of THIS team
    if (message == 'already_member' && user != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.statusInProgress.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.statusInProgress.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          TAvatar(name: user!.fullName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user!.fullName, style: AppTextStyles.labelMd,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                'Already a member of this team',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.statusInProgress, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const Icon(Icons.check_circle, color: AppColors.statusInProgress, size: 22),
        ]),
      );
    }

    // Found — show card with Add button
    if (user != null) {
      final inOtherTeam = message == 'other_team';
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              TAvatar(name: user!.fullName, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user!.fullName, style: AppTextStyles.labelMd,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    TStatusChip(label: user!.role, color: _roleColor),
                    TStatusChip(
                      label: user!.isActive ? 'Active' : 'Inactive',
                      color: user!.isActive
                          ? AppColors.statusDone
                          : AppColors.onSurfaceVariant,
                    ),
                  ]),
                ]),
              ),
              const Icon(Icons.person_outline, color: AppColors.gold, size: 22),
            ]),

            // Warning if user belongs to another team
            if (inOtherTeam) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.statusMedium.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.statusMedium),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This user is assigned to another team. Adding them here will move them to this team.',
                      style: AppTextStyles.bodySm.copyWith(fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: adding ? null : onAdd,
                icon: adding
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.person_add_outlined, size: 18),
                label: Text(
                  adding
                      ? 'Adding…'
                      : inOtherTeam
                          ? 'Move to This Team'
                          : 'Add to Team',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Member Card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.user, required this.onRemove});
  final ProfileModel user;
  final VoidCallback onRemove;

  Color get _roleColor {
    switch (user.role) {
      case 'admin':    return AppColors.primary;
      case 'manager':  return AppColors.gold;
      case 'employee': return AppColors.statusInProgress;
      case 'client':   return AppColors.statusMedium;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        TAvatar(name: user.fullName, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.fullName, style: AppTextStyles.labelMd,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              TStatusChip(label: user.role, color: _roleColor),
              const SizedBox(width: 6),
              TStatusChip(
                label: user.isActive ? 'Active' : 'Inactive',
                color: user.isActive ? AppColors.statusDone : AppColors.onSurfaceVariant,
              ),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'Options',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
          onSelected: (val) {
            if (val == 'privileges') {
              context.push('/users/${user.id}/privileges', extra: {
                'userName': user.fullName,
                'role':     user.role,
              });
            } else if (val == 'remove') {
              onRemove();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'privileges',
              child: Row(children: [
                Icon(Icons.tune_outlined, size: 16, color: AppColors.gold),
                SizedBox(width: 10),
                Text('Edit Privileges'),
              ]),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(children: [
                Icon(Icons.person_remove_outlined, size: 16, color: AppColors.error),
                SizedBox(width: 10),
                Text('Remove from team'),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}
