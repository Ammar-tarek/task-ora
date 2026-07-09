// lib/core/models/user_privileges_model.dart
// Per-user (sub-)privileges. Managed by admins for anyone, and by managers
// for members of their own team. Overrides the team-level defaults for the
// specific user when a row exists.

class UserPrivilegesModel {
  final String? id;
  final String  userId;
  final bool canManageAttendance;
  final bool canManageExpenses;
  final bool canManageTasks;
  final bool canManagePenalties;
  final bool canManageClients;
  final bool canCreateEmployees;
  final bool canViewFinance;

  const UserPrivilegesModel({
    this.id,
    required this.userId,
    required this.canManageAttendance,
    required this.canManageExpenses,
    required this.canManageTasks,
    required this.canManagePenalties,
    required this.canManageClients,
    required this.canCreateEmployees,
    required this.canViewFinance,
  });

  factory UserPrivilegesModel.defaults(String userId) => UserPrivilegesModel(
        userId: userId,
        canManageAttendance: true,
        canManageExpenses:   true,
        canManageTasks:      true,
        canManagePenalties:  true,
        canManageClients:    true,
        canCreateEmployees:  true,
        canViewFinance:      false,
      );

  factory UserPrivilegesModel.fromMap(Map<String, dynamic> m) => UserPrivilegesModel(
        id:                  m['id']                    as String?,
        userId:              m['user_id']               as String,
        canManageAttendance: m['can_manage_attendance'] as bool? ?? true,
        canManageExpenses:   m['can_manage_expenses']   as bool? ?? true,
        canManageTasks:      m['can_manage_tasks']      as bool? ?? true,
        canManagePenalties:  m['can_manage_penalties']  as bool? ?? true,
        canManageClients:    m['can_manage_clients']    as bool? ?? true,
        canCreateEmployees:  m['can_create_employees']  as bool? ?? true,
        canViewFinance:      m['can_view_finance']      as bool? ?? false,
      );

  Map<String, dynamic> toUpsertMap({String? updatedBy}) => {
        if (id != null) 'id': id,
        'user_id':               userId,
        'can_manage_attendance': canManageAttendance,
        'can_manage_expenses':   canManageExpenses,
        'can_manage_tasks':      canManageTasks,
        'can_manage_penalties':  canManagePenalties,
        'can_manage_clients':    canManageClients,
        'can_create_employees':  canCreateEmployees,
        'can_view_finance':      canViewFinance,
        if (updatedBy != null) 'updated_by': updatedBy,
        'updated_at':            DateTime.now().toIso8601String(),
      };

  UserPrivilegesModel copyWith({
    bool? canManageAttendance,
    bool? canManageExpenses,
    bool? canManageTasks,
    bool? canManagePenalties,
    bool? canManageClients,
    bool? canCreateEmployees,
    bool? canViewFinance,
  }) =>
      UserPrivilegesModel(
        id:                  id,
        userId:              userId,
        canManageAttendance: canManageAttendance ?? this.canManageAttendance,
        canManageExpenses:   canManageExpenses   ?? this.canManageExpenses,
        canManageTasks:      canManageTasks      ?? this.canManageTasks,
        canManagePenalties:  canManagePenalties  ?? this.canManagePenalties,
        canManageClients:    canManageClients    ?? this.canManageClients,
        canCreateEmployees:  canCreateEmployees  ?? this.canCreateEmployees,
        canViewFinance:      canViewFinance      ?? this.canViewFinance,
      );
}
