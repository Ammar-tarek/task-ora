// lib/core/services/revenue_create_scope.dart
// Decides which department (team id) a newly created MANUAL revenue entry must
// belong to. Mirrors TaskCreateScope: the department is always derived from
// trusted context — the user's verified role/team and the active workspace —
// never from a user-chosen dropdown.
//
//   • Admin / Super Admin: the active workspace (selected department) team id;
//     null means "All Departments" (no single department → the caller must
//     require a client instead, so the DB owner CHECK is satisfied).
//   • Manager / Employee: their verified team assignment. (They are blocked
//     from internal Finance by the router + RLS; this is only a safe default.)
//
// Pure and side-effect free so it is unit-testable. The database RLS and the
// crm_entries owner CHECK remain the real enforcement boundary.

import '../models/profile_model.dart';

class RevenueCreateScope {
  RevenueCreateScope._();

  /// Team id the new entry is assigned to. For admins this is [activeTeamId]
  /// (the resolved team of the active department workspace, or null for
  /// "All Departments"); for everyone else it is their own team.
  static String? departmentTeamIdFor(
    ProfileModel profile, {
    String? activeTeamId,
  }) {
    if (profile.isAdmin) return activeTeamId;
    return profile.teamId;
  }
}
