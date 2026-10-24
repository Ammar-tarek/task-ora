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
    test('employee: Tasks/Attendance/Penalties, NO Department Revenue', () {
      final keys = DashboardQuickActions.visibleKeys(_p(role: 'employee'));
      expect(keys, containsAll(['attendance', 'penalties', 'tasks']));
      expect(keys, isNot(contains('department_revenue')));
    });

    test('manager: NO Department Revenue (blocked from internal Finance)', () {
      final keys = DashboardQuickActions.visibleKeys(_p(role: 'manager'));
      expect(keys, isNot(contains('department_revenue')));
      expect(keys, containsAll(['attendance', 'penalties', 'tasks']));
    });

    test('admin keeps Department Revenue', () {
      expect(
        DashboardQuickActions.visibleKeys(_p(role: 'admin')),
        contains('department_revenue'),
      );
    });

    test('super admin keeps Department Revenue', () {
      expect(
        DashboardQuickActions.visibleKeys(
          _p(role: 'employee', superAdmin: true),
        ),
        contains('department_revenue'),
      );
    });

    test('null profile hides Department Revenue (safe default)', () {
      expect(
        DashboardQuickActions.showDepartmentRevenue(null),
        isFalse,
      );
    });
  });
}
