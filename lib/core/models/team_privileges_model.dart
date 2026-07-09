// lib/core/models/team_privileges_model.dart
// Stores per-team manager permissions managed by the admin.

class TeamPrivilegesModel {
  final String? id;
  final String  teamId;
  final bool canManageAttendance;
  final bool canManageExpenses;
  final bool canManageTasks;
  final bool canManagePenalties;
  final bool canManageClients;
  final bool canCreateEmployees;
  final bool canViewFinance;

  const TeamPrivilegesModel({
    this.id,
    required this.teamId,
    required this.canManageAttendance,
    required this.canManageExpenses,
    required this.canManageTasks,
    required this.canManagePenalties,
    required this.canManageClients,
    required this.canCreateEmployees,
    required this.canViewFinance,
  });

  factory TeamPrivilegesModel.defaults(String teamId) => TeamPrivilegesModel(
        teamId: teamId,
        canManageAttendance: true,
        canManageExpenses:   true,
        canManageTasks:      true,
        canManagePenalties:  true,
        canManageClients:    true,
        canCreateEmployees:  true,
        canViewFinance:      false,
      );

  factory TeamPrivilegesModel.fromMap(Map<String, dynamic> m) => TeamPrivilegesModel(
        id:                  m['id']                    as String?,
        teamId:              m['team_id']               as String,
        canManageAttendance: m['can_manage_attendance'] as bool? ?? true,
        canManageExpenses:   m['can_manage_expenses']   as bool? ?? true,
        canManageTasks:      m['can_manage_tasks']      as bool? ?? true,
        canManagePenalties:  m['can_manage_penalties']  as bool? ?? true,
        canManageClients:    m['can_manage_clients']    as bool? ?? true,
        canCreateEmployees:  m['can_create_employees']  as bool? ?? true,
        canViewFinance:      m['can_view_finance']      as bool? ?? false,
      );

  Map<String, dynamic> toUpsertMap() => {
        if (id != null) 'id': id,
        'team_id':               teamId,
        'can_manage_attendance': canManageAttendance,
        'can_manage_expenses':   canManageExpenses,
        'can_manage_tasks':      canManageTasks,
        'can_manage_penalties':  canManagePenalties,
        'can_manage_clients':    canManageClients,
        'can_create_employees':  canCreateEmployees,
        'can_view_finance':      canViewFinance,
        'updated_at':            DateTime.now().toIso8601String(),
      };

  TeamPrivilegesModel copyWith({
    bool? canManageAttendance,
    bool? canManageExpenses,
    bool? canManageTasks,
    bool? canManagePenalties,
    bool? canManageClients,
    bool? canCreateEmployees,
    bool? canViewFinance,
  }) =>
      TeamPrivilegesModel(
        id:                  id,
        teamId:              teamId,
        canManageAttendance: canManageAttendance ?? this.canManageAttendance,
        canManageExpenses:   canManageExpenses   ?? this.canManageExpenses,
        canManageTasks:      canManageTasks      ?? this.canManageTasks,
        canManagePenalties:  canManagePenalties  ?? this.canManagePenalties,
        canManageClients:    canManageClients    ?? this.canManageClients,
        canCreateEmployees:  canCreateEmployees  ?? this.canCreateEmployees,
        canViewFinance:      canViewFinance      ?? this.canViewFinance,
      );
}
