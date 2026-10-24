// lib/core/services/task_create_scope.dart
// Decides which department (team id) a newly created task must belong to.
//
// The department is always derived from trusted context — the user's verified
// role/team and the active workspace — never from a client-supplied value:
//   • Admin / Super Admin: the active workspace (selected department); null
//     means "All Departments", i.e. a company-wide task with no department.
//   • Manager / Employee: their verified team assignment, regardless of any
//     active-workspace value (they cannot create into another department).
//
// Pure and side-effect free so it is unit-testable and reused by the New Task
// form. The database RLS remains the real enforcement boundary.

import '../models/profile_model.dart';

class TaskCreateScope {
  TaskCreateScope._();

  static String? departmentTeamIdFor(
    ProfileModel profile, {
    String? activeTeamId,
  }) {
    if (profile.isAdmin) return activeTeamId;
    return profile.teamId;
  }
}
