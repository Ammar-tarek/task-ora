// lib/core/router/workspace_routing.dart
// Pure, side-effect-free resolution of a user's post-login entry route and the
// /workspaces access guard. Extracted from the GoRouter redirect so the
// role→entry mapping is unit-testable without spinning up a router.
//
// IMPORTANT: this is navigation only. Real access control is the database RLS.
// The role is read from the verified profile; it must never be the sole basis
// for granting data access (see DEPARTMENT_MIGRATION_ASSESSMENT.md §4).

import '../constants/departments.dart';
import '../models/profile_model.dart';
import 'app_routes.dart';

class WorkspaceRouting {
  WorkspaceRouting._();

  /// A Production-department manager/employee is restricted to a Calendar-only
  /// experience. Admins / super admins (global) and clients are NEVER restricted
  /// here — their experiences are unchanged. [department] is resolved from the
  /// user's team (teams.department) by AuthNotifier at login.
  static bool isProductionCalendarOnly(
    ProfileModel? profile,
    Department? department,
  ) {
    if (profile == null) return false;
    if (profile.isAdmin || profile.isClient) return false; // isAdmin incl. super
    return department == Department.production;
  }

  /// Redirect target for the department-resolution gate. While a required
  /// department is [pending] (loading or failed), hold the user on /resolving
  /// (returning null when they are already there, to avoid a redirect loop).
  /// Returns null when not pending — the caller then applies normal routing.
  static String? departmentGateRedirect(
    String location, {
    required bool pending,
  }) {
    if (!pending) return null;
    return location == AppRoutes.resolving ? null : AppRoutes.resolving;
  }

  /// A global admin / super admin is confined to Calendar ONLY while the
  /// Production department workspace is the one in view ([effectiveDepartment]).
  /// Outside Production (another department, or "All Departments") the admin is
  /// unchanged. Unlike a scoped user this is driven by the SELECTED workspace,
  /// not the profile team, and the admin keeps the workspace selector to switch
  /// out (see [productionRedirect] allowWorkspaces).
  static bool isAdminProductionCalendarOnly(
    ProfileModel? profile,
    Department? effectiveDepartment,
  ) {
    if (profile == null || !profile.isAdmin) return false; // isAdmin incl. super
    return effectiveDepartment == Department.production;
  }

  /// Redirect target for a Production calendar-only user. Returns null when the
  /// user is not restricted, or is already somewhere under /calendar (so the
  /// existing Calendar screen + its subroutes work untouched). Anything else is
  /// sent to /calendar — this is the hard block for direct-route access.
  ///
  /// [allowWorkspaces] keeps /workspaces reachable so a calendar-only ADMIN can
  /// always switch back out of the Production workspace (their escape hatch).
  /// Scoped users (manager/employee) pass false — they have no selector.
  static String? productionRedirect(
    String location, {
    required bool calendarOnly,
    bool allowWorkspaces = false,
  }) {
    if (!calendarOnly) return null;
    if (location == AppRoutes.calendar ||
        location.startsWith('${AppRoutes.calendar}/')) {
      return null;
    }
    // Settings stays reachable so a Production manager/employee can see their
    // profile and sign out (Settings also has no other-department data).
    if (location == '/settings' || location.startsWith('/settings/')) {
      return null;
    }
    if (allowWorkspaces && location == AppRoutes.workspaces) return null;
    return AppRoutes.calendar;
  }

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
