// lib/features/dashboard/dashboard_quick_actions.dart
// Pure role rule for which dashboard Quick Actions a user may see, so the rule
// is unit-testable without building the whole dashboard. Mirrors the router
// guards (employees are redirected away from /finance) and the penalties screen
// (employees see only their own records).

import '../../core/models/profile_model.dart';

class DashboardQuickActions {
  DashboardQuickActions._();

  /// Action keys visible to [profile], in display order.
  ///  - attendance: everyone (own attendance actions).
  ///  - penalties: everyone (employees see only their OWN records; managers/
  ///    admins get management on the penalties screen itself).
  ///  - analytics: management (admin/manager) — the department reporting entry
  ///    that replaced the old Finance shortcut. Scoped by role in the screen.
  ///  - tasks: everyone.
  static List<String> visibleKeys(ProfileModel? profile) {
    final isAdmin = profile?.isAdmin == true;
    final isManager = profile?.isManager == true;
    return [
      'attendance',
      'penalties',
      // Analytics replaces the old department Finance entry as the department's
      // reporting destination. Admin → all/selected dept; manager → own team
      // (AdvancedAnalyticsScreen scopes by teamIds). Company Finance / Company
      // Ledger stay reachable via their own routes — only this shortcut changed.
      if (isAdmin || isManager) 'analytics',
      // Team performance hub — management only (admin or manager). Each query
      // is department-scoped; employees never see it.
      if (isAdmin || isManager) 'team',
      // Department-scoped Client directory — management only.
      if (isAdmin || isManager) 'clients',
      'tasks',
    ];
  }

  /// Analytics = department reporting, for management (admin/manager).
  static bool showAnalytics(ProfileModel? profile) =>
      visibleKeys(profile).contains('analytics');

  /// Department Client directory — management only (admin/manager).
  static bool showClients(ProfileModel? profile) =>
      visibleKeys(profile).contains('clients');

  /// Team performance hub is for authorized management only (admin/manager).
  static bool showTeam(ProfileModel? profile) =>
      visibleKeys(profile).contains('team');
}
