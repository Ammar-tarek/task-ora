// test/workspace_routing_test.dart
// M2 — role-based entry point + /workspaces guard. Pure, no Flutter bindings.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
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

  group('isProductionCalendarOnly (Production = Calendar-only)', () {
    test('production manager and employee → true', () {
      expect(
        WorkspaceRouting.isProductionCalendarOnly(
            _p(role: 'manager'), Department.production),
        isTrue,
      );
      expect(
        WorkspaceRouting.isProductionCalendarOnly(
            _p(role: 'employee'), Department.production),
        isTrue,
      );
    });

    test('admin / super admin / client → false even in Production', () {
      expect(
        WorkspaceRouting.isProductionCalendarOnly(
            _p(role: 'admin'), Department.production),
        isFalse,
      );
      expect(
        WorkspaceRouting.isProductionCalendarOnly(
            _p(role: 'admin', superAdmin: true), Department.production),
        isFalse,
      );
      expect(
        WorkspaceRouting.isProductionCalendarOnly(
            _p(role: 'client'), Department.production),
        isFalse,
      );
    });

    test('other departments → false (isolation)', () {
      for (final d in const [
        Department.marketing,
        Department.montage,
        Department.sales,
        Department.studio,
      ]) {
        expect(
          WorkspaceRouting.isProductionCalendarOnly(_p(role: 'employee'), d),
          isFalse,
          reason: d.toString(),
        );
      }
    });

    test('null department or null profile → false', () {
      expect(
        WorkspaceRouting.isProductionCalendarOnly(_p(role: 'employee'), null),
        isFalse,
      );
      expect(
        WorkspaceRouting.isProductionCalendarOnly(null, Department.production),
        isFalse,
      );
    });
  });

  group('productionRedirect (direct-route block)', () {
    test('not restricted → null (no redirect)', () {
      expect(
        WorkspaceRouting.productionRedirect('/dashboard', calendarOnly: false),
        isNull,
      );
    });

    test('restricted + already under /calendar → null', () {
      expect(
        WorkspaceRouting.productionRedirect('/calendar', calendarOnly: true),
        isNull,
      );
      expect(
        WorkspaceRouting.productionRedirect('/calendar/enhanced',
            calendarOnly: true),
        isNull,
      );
    });

    test('restricted + any other route → /calendar', () {
      for (final loc in const [
        '/dashboard',
        '/tasks',
        '/tasks/table',
        '/finance',
        '/workspaces',
        '/analytics',
        '/expenses',
        '/users',
        '/teams',
        '/notifications',
      ]) {
        expect(
          WorkspaceRouting.productionRedirect(loc, calendarOnly: true),
          '/calendar',
          reason: loc,
        );
      }
    });

    test('restricted + /settings → null (profile + sign out reachable)', () {
      expect(
        WorkspaceRouting.productionRedirect('/settings', calendarOnly: true),
        isNull,
      );
      expect(
        WorkspaceRouting.productionRedirect('/settings/x', calendarOnly: true),
        isNull,
      );
    });
  });

  group('isAdminProductionCalendarOnly (admin viewing Production)', () {
    test('admin / super admin viewing Production → true', () {
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            _p(role: 'admin'), Department.production),
        isTrue,
      );
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            _p(role: 'admin', superAdmin: true), Department.production),
        isTrue,
      );
    });

    test('admin viewing another department or All (null) → false', () {
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            _p(role: 'admin'), Department.marketing),
        isFalse,
      );
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(_p(role: 'admin'), null),
        isFalse,
      );
    });

    test('non-admin (manager/employee/client) → false here', () {
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            _p(role: 'manager'), Department.production),
        isFalse,
      );
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            _p(role: 'client'), Department.production),
        isFalse,
      );
    });

    test('null profile → false', () {
      expect(
        WorkspaceRouting.isAdminProductionCalendarOnly(
            null, Department.production),
        isFalse,
      );
    });
  });

  group('productionRedirect — admin keeps the /workspaces escape', () {
    test('admin calendar-only: /workspaces stays reachable', () {
      expect(
        WorkspaceRouting.productionRedirect('/workspaces',
            calendarOnly: true, allowWorkspaces: true),
        isNull,
      );
    });
    test('admin calendar-only: other routes still → /calendar', () {
      expect(
        WorkspaceRouting.productionRedirect('/dashboard',
            calendarOnly: true, allowWorkspaces: true),
        '/calendar',
      );
    });
    test('scoped user (no escape): /workspaces → /calendar', () {
      expect(
        WorkspaceRouting.productionRedirect('/workspaces', calendarOnly: true),
        '/calendar',
      );
    });
  });
}
