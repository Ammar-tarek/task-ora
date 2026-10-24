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
  ///  - department_revenue: admin / super admin only. Managers and employees
  ///    are blocked from internal Finance by the /finance router guard, so the
  ///    action is hidden for them here too.
  ///  - tasks: everyone.
  static List<String> visibleKeys(ProfileModel? profile) {
    final isAdmin = profile?.isAdmin == true;
    return [
      'attendance',
      'penalties',
      if (isAdmin) 'department_revenue',
      'tasks',
    ];
  }

  static bool showDepartmentRevenue(ProfileModel? profile) =>
      visibleKeys(profile).contains('department_revenue');
}
