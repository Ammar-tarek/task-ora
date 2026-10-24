// test/task_create_scope_test.dart
// Verifies new tasks are created in the correct authorized department and that
// a client-supplied / active-workspace value cannot override a scoped user.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/services/task_create_scope.dart';

ProfileModel _p({
  required String role,
  String? teamId,
  bool superAdmin = false,
}) => ProfileModel(
  id: 'u-$role',
  role: role,
  fullName: 'U',
  status: 'active',
  teamId: teamId,
  timezone: 'UTC',
  preferredLanguage: 'en',
  createdAt: '2026-01-01',
  isSuperAdminFlag: superAdmin,
);

void main() {
  group('TaskCreateScope.departmentTeamIdFor', () {
    test('admin uses the active workspace department', () {
      expect(
        TaskCreateScope.departmentTeamIdFor(
          _p(role: 'admin', teamId: 'admins-team'),
          activeTeamId: 'marketing-team',
        ),
        'marketing-team',
      );
    });

    test('admin in All Departments creates a company-wide task (null)', () {
      expect(
        TaskCreateScope.departmentTeamIdFor(
          _p(role: 'admin'),
          activeTeamId: null,
        ),
        isNull,
      );
    });

    test('super admin behaves like admin (uses active workspace)', () {
      expect(
        TaskCreateScope.departmentTeamIdFor(
          _p(role: 'admin', superAdmin: true),
          activeTeamId: 'sales-team',
        ),
        'sales-team',
      );
    });

    test('manager is bound to their own team, ignoring active workspace', () {
      expect(
        TaskCreateScope.departmentTeamIdFor(
          _p(role: 'manager', teamId: 'montage-team'),
          activeTeamId: 'marketing-team', // must NOT be honored
        ),
        'montage-team',
      );
    });

    test('employee is bound to their own team, ignoring active workspace', () {
      expect(
        TaskCreateScope.departmentTeamIdFor(
          _p(role: 'employee', teamId: 'production-team'),
          activeTeamId: 'sales-team',
        ),
        'production-team',
      );
    });
  });
}
