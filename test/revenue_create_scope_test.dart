// test/revenue_create_scope_test.dart
// Automatic department assignment for new manual revenue entries: the
// department is derived from the active workspace (admins) or the user's own
// team (everyone else), never from a user-chosen value.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/services/revenue_create_scope.dart';

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
  group('RevenueCreateScope.departmentTeamIdFor', () {
    test('admin inherits the active workspace department', () {
      expect(
        RevenueCreateScope.departmentTeamIdFor(
          _p(role: 'admin', teamId: 'admins-team'),
          activeTeamId: 'marketing-team',
        ),
        'marketing-team',
      );
    });

    test('admin in All Departments resolves to null (needs client instead)', () {
      expect(
        RevenueCreateScope.departmentTeamIdFor(
          _p(role: 'admin'),
          activeTeamId: null,
        ),
        isNull,
      );
    });

    test('super admin behaves like admin (uses active workspace)', () {
      expect(
        RevenueCreateScope.departmentTeamIdFor(
          _p(role: 'employee', superAdmin: true),
          activeTeamId: 'sales-team',
        ),
        'sales-team',
      );
    });

    test('manager cannot create into another department (own team wins)', () {
      expect(
        RevenueCreateScope.departmentTeamIdFor(
          _p(role: 'manager', teamId: 'montage-team'),
          activeTeamId: 'marketing-team', // must be ignored
        ),
        'montage-team',
      );
    });

    test('employee is bound to their own team', () {
      expect(
        RevenueCreateScope.departmentTeamIdFor(
          _p(role: 'employee', teamId: 'production-team'),
          activeTeamId: 'sales-team',
        ),
        'production-team',
      );
    });
  });
}
