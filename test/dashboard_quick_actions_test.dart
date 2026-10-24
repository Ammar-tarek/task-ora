// test/dashboard_quick_actions_test.dart
// Role visibility for dashboard Quick Actions.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/features/dashboard/dashboard_quick_actions.dart';

ProfileModel _p({required String role, bool superAdmin = false}) => ProfileModel(
  id: 'u',
  role: role,
  fullName: 'U',
  status: 'active',
  timezone: 'UTC',
  preferredLanguage: 'en',
  createdAt: '2026-01-01',
  isSuperAdminFlag: superAdmin,
);

void main() {
  group('DashboardQuickActions.visibleKeys', () {
    test('employee: Tasks/Attendance/Penalties, NO Analytics, NO Team', () {
      final keys = DashboardQuickActions.visibleKeys(_p(role: 'employee'));
      expect(keys, containsAll(['attendance', 'penalties', 'tasks']));
      expect(keys, isNot(contains('analytics')));
      expect(keys, isNot(contains('department_revenue'))); // old entry gone
      expect(keys, isNot(contains('team')));
      expect(DashboardQuickActions.showTeam(_p(role: 'employee')), isFalse);
      expect(DashboardQuickActions.showAnalytics(_p(role: 'employee')), isFalse);
    });

    test('manager: Analytics + Team + Clients visible, NO old Finance entry', () {
      final keys = DashboardQuickActions.visibleKeys(_p(role: 'manager'));
      expect(keys, isNot(contains('department_revenue')));
      expect(keys, containsAll(['attendance', 'penalties', 'tasks', 'team', 'analytics', 'clients']));
      expect(DashboardQuickActions.showAnalytics(_p(role: 'manager')), isTrue);
      expect(DashboardQuickActions.showClients(_p(role: 'manager')), isTrue);
    });

    test('admin gets Analytics, Team, Clients; not the old Finance entry', () {
      final keys = DashboardQuickActions.visibleKeys(_p(role: 'admin'));
      expect(keys, contains('analytics'));
      expect(keys, contains('team'));
      expect(keys, contains('clients'));
      expect(keys, isNot(contains('department_revenue')));
    });

    test('employee has no Clients entry', () {
      expect(DashboardQuickActions.showClients(_p(role: 'employee')), isFalse);
    });

    test('super admin gets Analytics', () {
      expect(
        DashboardQuickActions.visibleKeys(
          _p(role: 'employee', superAdmin: true),
        ),
        contains('analytics'),
      );
    });

    test('null profile hides Analytics (safe default)', () {
      expect(DashboardQuickActions.showAnalytics(null), isFalse);
    });
  });
}
