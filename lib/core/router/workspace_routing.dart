// lib/core/router/workspace_routing.dart
// Pure, side-effect-free resolution of a user's post-login entry route and the
// /workspaces access guard. Extracted from the GoRouter redirect so the
// role→entry mapping is unit-testable without spinning up a router.
//
// IMPORTANT: this is navigation only. Real access control is the database RLS.
// The role is read from the verified profile; it must never be the sole basis
// for granting data access (see DEPARTMENT_MIGRATION_ASSESSMENT.md §4).

import '../models/profile_model.dart';
import 'app_routes.dart';

class WorkspaceRouting {
  WorkspaceRouting._();

  /// Where a freshly-authenticated user should land, by role.
  /// - Client: the existing client-facing Tasks workspace (unchanged).
  /// - Admin / Super Admin: the department workspace entry screen.
  /// - Manager: their dashboard. Employee: their tasks. (Existing behavior.)
  static String entryRouteFor(ProfileModel? profile) {
    if (profile == null) return AppRoutes.login;
    if (profile.isClient) return AppRoutes.tasks;
    if (profile.isAdmin) return AppRoutes.workspaces; // admin incl. super admin
    if (profile.isManager) return AppRoutes.dashboard;
    return AppRoutes.tasks; // employee
  }

  /// Only global users (admin / super admin) may open the /workspaces entry
  /// screen. Anyone else is sent to their own entry route. Returns null when no
  /// redirect is needed.
  static String? guardWorkspaces(ProfileModel? profile) {
    if (profile != null && profile.isAdmin) return null;
    return entryRouteFor(profile);
  }
}
