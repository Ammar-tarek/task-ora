// test/workspace_routing_test.dart
// M2 — role-based entry point + /workspaces guard. Pure, no Flutter bindings.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/router/workspace_routing.dart';

ProfileModel _p({required String role, bool superAdmin = false}) =>
    ProfileModel(
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
  group('entryRouteFor', () {
    test('no profile → login', () {
      expect(WorkspaceRouting.entryRouteFor(null), '/login');
    });

    test('admin and super admin → workspaces selector', () {
      expect(WorkspaceRouting.entryRouteFor(_p(role: 'admin')), '/workspaces');
      expect(
        WorkspaceRouting.entryRouteFor(_p(role: 'admin', superAdmin: true)),
        '/workspaces',
      );
    });

    test('manager → dashboard, employee → tasks (existing behavior)', () {
      expect(WorkspaceRouting.entryRouteFor(_p(role: 'manager')), '/dashboard');
      expect(WorkspaceRouting.entryRouteFor(_p(role: 'employee')), '/tasks');
    });

    test('client → client-facing tasks workspace (preserved)', () {
      expect(WorkspaceRouting.entryRouteFor(_p(role: 'client')), '/tasks');
    });
  });

  group('guardWorkspaces', () {
    test('admin / super admin may stay (no redirect)', () {
      expect(WorkspaceRouting.guardWorkspaces(_p(role: 'admin')), isNull);
      expect(
        WorkspaceRouting.guardWorkspaces(_p(role: 'admin', superAdmin: true)),
        isNull,
      );
    });

    test('manager/employee/client are redirected to their own landing', () {
      expect(
        WorkspaceRouting.guardWorkspaces(_p(role: 'manager')),
        '/dashboard',
      );
      expect(WorkspaceRouting.guardWorkspaces(_p(role: 'employee')), '/tasks');
      expect(WorkspaceRouting.guardWorkspaces(_p(role: 'client')), '/tasks');
    });

    test('no profile → login', () {
      expect(WorkspaceRouting.guardWorkspaces(null), '/login');
    });
  });
}
