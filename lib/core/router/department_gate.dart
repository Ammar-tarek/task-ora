// lib/core/router/department_gate.dart
// Pure, side-effect-free department-resolution gate. Decides — without touching
// Flutter or Supabase — whether a user's department must be resolved before they
// may enter the workspace, and whether the router must HOLD them while that
// resolution is loading or has failed. Fail CLOSED: a required-but-unresolved
// department never grants normal navigation.
//
// Mirrors — never replaces — DB RLS (see DEPARTMENT_MIGRATION_ASSESSMENT.md §4).

import '../models/profile_model.dart';

/// Lifecycle of the per-user department lookup (teams.department via team_id).
enum DepartmentResolution {
  /// No lookup needed: admin / super admin / client, or a user with no team
  /// (the latter is handled by the existing pending/onboarding flow).
  notRequired,

  /// Lookup in flight.
  loading,

  /// Lookup finished and the department (or a definite "no department" for a
  /// known team) is known.
  resolved,

  /// Lookup threw, or the team row was missing despite a non-null team_id.
  /// Treated as BLOCKING — never as permission to enter the full app.
  failed,
}

class DepartmentGate {
  DepartmentGate._();

  /// A manager/employee with a team must have their department resolved before
  /// entering the workspace. Admins/super admins and clients never need it;
  /// a null team_id is left to the existing pending/onboarding flow.
  static bool isRequired(ProfileModel? profile) {
    if (profile == null) return false;
    if (profile.isAdmin || profile.isClient) return false; // isAdmin incl. super
    return profile.teamId != null;
  }

  /// The router must hold the user on the resolving screen while a REQUIRED
  /// department is still loading or has failed (fail closed).
  static bool isPending(ProfileModel? profile, DepartmentResolution state) =>
      isRequired(profile) &&
      (state == DepartmentResolution.loading ||
          state == DepartmentResolution.failed);

  /// Pending specifically because the lookup failed — the resolving screen shows
  /// an error + Retry instead of a spinner.
  static bool isFailed(ProfileModel? profile, DepartmentResolution state) =>
      isRequired(profile) && state == DepartmentResolution.failed;
}
