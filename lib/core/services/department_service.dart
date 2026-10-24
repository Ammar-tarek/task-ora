// lib/core/services/department_service.dart
// Single source of truth for "which department workspaces can this user open?".
//
// Pure / side-effect-free so it is unit-testable and can be reused by routing,
// the workspace switcher, and repositories. It intentionally mirrors — but does
// not replace — the database RLS, which remains the real enforcement boundary
// (see DEPARTMENT_MIGRATION_ASSESSMENT.md §4).

import '../constants/departments.dart';
import '../models/profile_model.dart';
import '../models/team_model.dart';

class DepartmentService {
  DepartmentService._();

  /// Global tiers (Admin and Super Admin) can reach every department.
  /// [ProfileModel.isAdmin] already returns true for super admins.
  static bool isGlobal(ProfileModel profile) => profile.isAdmin;

  /// Company-wide Expenses is admin-only. This matches the DB RLS exactly:
  /// `expenses` exposes a single admin policy and has no team scoping, so
  /// managers/employees have no access regardless of privilege flags.
  static bool canAccessExpenses(ProfileModel profile) => isGlobal(profile);

  /// Departments [profile] may open.
  /// - Admin / Super Admin: all five.
  /// - Manager / Employee: only their own team's department (when the team maps
  ///   to a known department; the internal "Admins" team maps to none).
  /// - Client: none — clients use the dedicated client-facing workspace.
  static List<Department> accessibleDepartments(
    ProfileModel profile, {
    TeamModel? team,
  }) {
    if (profile.isClient) return const <Department>[];
    if (isGlobal(profile)) return Departments.all;
    final resolved = team == null ? null : Departments.fromTeam(team);
    return resolved == null ? const <Department>[] : <Department>[resolved];
  }

  /// Whether [profile] may open a specific [department].
  static bool canAccess(
    ProfileModel profile,
    Department department, {
    TeamModel? team,
  }) => accessibleDepartments(profile, team: team).contains(department);
}
