// test/deactivation_policy_test.dart
// Pure client-side rules for the Team deactivate/reactivate action. The server
// (admin-user-ops set_active) is authoritative; these only gate UI visibility.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/features/team/deactivation_policy.dart';

ProfileModel _p({
  required String id,
  required String role,
  bool superAdmin = false,
}) => ProfileModel(
  id: id,
  role: role,
  fullName: id,
  status: 'active',
  timezone: 'UTC',
  preferredLanguage: 'en',
  createdAt: '2026-01-01',
  isSuperAdminFlag: superAdmin,
);

void main() {
  group('DeactivationPolicy.canManage', () {
    test('admin + super admin can manage; others cannot', () {
      expect(DeactivationPolicy.canManage(_p(id: 'a', role: 'admin')), isTrue);
      expect(
        DeactivationPolicy.canManage(_p(id: 's', role: 'employee', superAdmin: true)),
        isTrue,
      );
      expect(DeactivationPolicy.canManage(_p(id: 'm', role: 'manager')), isFalse);
      expect(DeactivationPolicy.canManage(_p(id: 'e', role: 'employee')), isFalse);
      expect(DeactivationPolicy.canManage(null), isFalse);
    });
  });

  group('DeactivationPolicy.canChangeStatus', () {
    final admin = _p(id: 'admin-1', role: 'admin');
    final superAdmin = _p(id: 'super-1', role: 'admin', superAdmin: true);

    test('admin may change a regular employee', () {
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: admin,
          targetId: 'emp-1',
          targetRole: 'employee',
          targetIsSuperAdmin: false,
        ),
        isTrue,
      );
    });

    test('self-deactivation is always blocked', () {
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: admin,
          targetId: admin.id,
          targetRole: 'admin',
          targetIsSuperAdmin: false,
        ),
        isFalse,
      );
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: superAdmin,
          targetId: superAdmin.id,
          targetRole: 'admin',
          targetIsSuperAdmin: true,
        ),
        isFalse,
      );
    });

    test('a plain admin may NOT change another admin', () {
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: admin,
          targetId: 'admin-2',
          targetRole: 'admin',
          targetIsSuperAdmin: false,
        ),
        isFalse,
      );
    });

    test('only a super admin may change another admin / super admin', () {
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: superAdmin,
          targetId: 'admin-2',
          targetRole: 'admin',
          targetIsSuperAdmin: false,
        ),
        isTrue,
      );
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: superAdmin,
          targetId: 'super-2',
          targetRole: 'admin',
          targetIsSuperAdmin: true,
        ),
        isTrue,
      );
    });

    test('non-admin viewers can never change anyone', () {
      final manager = _p(id: 'mgr', role: 'manager');
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: manager,
          targetId: 'emp-1',
          targetRole: 'employee',
          targetIsSuperAdmin: false,
        ),
        isFalse,
      );
      expect(
        DeactivationPolicy.canChangeStatus(
          viewer: null,
          targetId: 'emp-1',
          targetRole: 'employee',
          targetIsSuperAdmin: false,
        ),
        isFalse,
      );
    });
  });
}
