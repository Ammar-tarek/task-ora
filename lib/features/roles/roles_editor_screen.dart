// lib/features/roles/roles_editor_screen.dart
// Roles & Privileges — shows real users from Supabase grouped by role.
// Admin can change any user's role. Uses adminClient to bypass RLS.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/profile_model.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';

const _roleOrder = ['admin', 'manager', 'employee', 'client'];

const _roleLabels = {
  'admin': 'Admin',
  'manager': 'Manager',
  'employee': 'Employee',
  'client': 'Client',
};

final _roleColors = {
  'admin': AppColors.primary,
  'manager': AppColors.gold,
  'employee': AppColors.statusInProgress,
  'client': AppColors.statusMedium,
};

const _roleDescriptions = {
  'admin': 'Full access to all features, users, finance and settings.',
  'manager': 'Manages team tasks, attendance, meetings and team finance.',
  'employee': 'Views own tasks and calendar. Can log attendance.',
  'client': 'Views own tasks and finance. Can book meetings.',
};

class RolesEditorScreen extends StatefulWidget {
  const RolesEditorScreen({super.key});
  @override
  State<RolesEditorScreen> createState() => _RolesEditorScreenState();
}

class _RolesEditorScreenState extends State<RolesEditorScreen> {
  String _selectedRole = 'employee';
  List<ProfileModel> _allUsers = [];
  bool _loading = true;
  String? _error;

  // Admin: manages everyone and can change roles.
  // Manager: scoped to their own team and can only edit privileges.
  bool _isAdmin = false;
  String? _scopeTeamId; // non-null for managers
  String? _myId; // current user — managers cannot edit themselves

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = context.read<AuthNotifier>().profile;
      _isAdmin = profile?.isAdmin == true;
      _scopeTeamId = _isAdmin ? null : profile?.teamId;
      _myId = profile?.id;
      _selectedRole = _isAdmin ? 'admin' : 'employee';
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = SupabaseService.adminClient.from('profiles').select();
      // Managers only see their own team (members + their clients).
      if (!_isAdmin && _scopeTeamId != null) {
        query = query.eq('team_id', _scopeTeamId!);
      }
      final data = await query.order('full_name');
      if (mounted) {
        setState(() {
          _allUsers = (data as List)
              .map((m) => ProfileModel.fromMap(m as Map<String, dynamic>))
              // Managers cannot see/edit their own privileges.
              .where((u) => _isAdmin || u.id != _myId)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString();
        });
    }
  }

  List<ProfileModel> get _usersForRole =>
      _allUsers.where((u) => u.role == _selectedRole).toList();

  Map<String, int> get _counts => {
    for (final r in _roleOrder) r: _allUsers.where((u) => u.role == r).length,
  };

  Future<void> _changeRole(ProfileModel user, String newRole) async {
    if (user.role == newRole) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Change Role', style: AppTextStyles.headlineSm),
        content: Text(
          'Change ${user.fullName} from ${_roleLabels[user.role] ?? user.role} '
          'to ${_roleLabels[newRole] ?? newRole}?',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupabaseService.adminClient
          .from('profiles')
          .update({'role': newRole})
          .eq('id', user.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName} is now ${_roleLabels[newRole]}'),
            backgroundColor: AppColors.statusDone,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change role: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isAdmin ? 'Roles & Privileges' : 'Team Privileges'),
            if (!_isAdmin)
              Text(
                'Your team only',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  Text('Failed to load users', style: AppTextStyles.labelMd),
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Role sidebar ──────────────────────────────────────────
                Container(
                  width: 130,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    border: Border(
                      right: BorderSide(color: AppColors.outlineVariant),
                    ),
                  ),
                  child: ListView(
                    children: _roleOrder.map((r) {
                      final isSelected = r == _selectedRole;
                      final color = _roleColors[r] ?? AppColors.primary;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedRole = r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            border: isSelected
                                ? const Border(
                                    left: BorderSide(
                                      color: AppColors.gold,
                                      width: 3,
                                    ),
                                  )
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      _roleLabels[r] ?? r,
                                      style: AppTextStyles.labelMd.copyWith(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.onSurface,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${counts[r] ?? 0} user${(counts[r] ?? 0) != 1 ? 's' : ''}',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: isSelected
                                      ? Colors.white60
                                      : AppColors.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // ── Role detail + users ───────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role header
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color:
                                    _roleColors[_selectedRole] ??
                                    AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _roleLabels[_selectedRole] ?? _selectedRole,
                              style: AppTextStyles.headlineSm,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _roleDescriptions[_selectedRole] ?? '',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'USERS WITH THIS ROLE',
                          style: AppTextStyles.labelCaps,
                        ),
                        const SizedBox(height: 10),

                        // User list for this role
                        if (_usersForRole.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_off_outlined,
                                  size: 18,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'No users with this role',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._usersForRole.map(
                            (user) => _UserRoleCard(
                              user: user,
                              canChangeRole: _isAdmin,
                              onChangeRole: (newRole) =>
                                  _changeRole(user, newRole),
                              onEditPrivileges: () => context.push(
                                '/users/${user.id}/privileges',
                                extra: {
                                  'userName': user.fullName,
                                  'role': user.role,
                                },
                              ),
                            ),
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

// ── User role card ─────────────────────────────────────────────────────────────

class _UserRoleCard extends StatelessWidget {
  const _UserRoleCard({
    required this.user,
    required this.onChangeRole,
    required this.canChangeRole,
    this.onEditPrivileges,
  });
  final ProfileModel user;
  final ValueChanged<String> onChangeRole;
  final bool canChangeRole;
  final VoidCallback? onEditPrivileges;

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[user.role] ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          TAvatar(name: user.fullName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: AppTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    TStatusChip(
                      label: user.isActive ? 'Active' : 'Inactive',
                      color: user.isActive
                          ? AppColors.statusDone
                          : AppColors.onSurfaceVariant,
                    ),
                    if (user.teamId != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.group_outlined,
                        size: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Single control: tap the role chip to open a menu. Admins get role
          // options AND "Edit Privileges"; managers get "Edit Privileges" only.
          PopupMenuButton<String>(
            tooltip: 'Options',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (val) {
              if (val == 'privileges') {
                onEditPrivileges?.call();
              } else if (val.startsWith('role:')) {
                onChangeRole(val.substring(5));
              }
            },
            itemBuilder: (_) => [
              // Role options (admin only, and not for other admins)
              if (canChangeRole && !user.isAdmin) ...[
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text('CHANGE ROLE', style: AppTextStyles.labelCaps),
                ),
                ..._roleOrder.map(
                  (r) => PopupMenuItem<String>(
                    value: 'role:$r',
                    child: Row(
                      children: [
                        Icon(
                          r == user.role ? Icons.check : Icons.circle_outlined,
                          size: 16,
                          color: _roleColors[r] ?? AppColors.onSurface,
                        ),
                        const SizedBox(width: 10),
                        Text(_roleLabels[r] ?? r),
                      ],
                    ),
                  ),
                ),
                const PopupMenuDivider(),
              ],
              // Privileges option (everyone in scope)
              if (onEditPrivileges != null)
                const PopupMenuItem<String>(
                  value: 'privileges',
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune_outlined,
                        size: 16,
                        color: AppColors.gold,
                      ),
                      SizedBox(width: 10),
                      Text('Edit Privileges'),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _roleLabels[user.role] ?? user.role,
                    style: AppTextStyles.labelMd.copyWith(color: color),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
