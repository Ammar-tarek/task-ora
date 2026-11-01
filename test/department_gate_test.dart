// test/department_gate_test.dart
// Fail-CLOSED department-resolution gate. Pure (no Flutter bindings, no Supabase).
// Proves a required-but-unresolved department never grants normal navigation.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/router/department_gate.dart';
import 'package:task_ora/core/router/workspace_routing.dart';

ProfileModel _p({
  required String role,
  bool superAdmin = false,
  String? teamId = 'team-1',
}) =>
    ProfileModel(
      id: 'u',
      role: role,
      fullName: 'U',
      status: 'active',
      teamId: teamId,
      timezone: 'UTC',
      preferredLanguage: 'en',
      createdAt: '2026-01-01',
      isSuperAdminFlag: superAdmin,
    );

// Mirrors AuthNotifier.isProductionOnly: true only when RESOLVED + production.
bool _isProductionOnly(ProfileModel p, DepartmentResolution s, Department? d) =>
    s == DepartmentResolution.resolved &&
    WorkspaceRouting.isProductionCalendarOnly(p, d);

void main() {
  group('isRequired', () {
    test('manager/employee with a team → required', () {
      expect(DepartmentGate.isRequired(_p(role: 'manager')), isTrue);
      expect(DepartmentGate.isRequired(_p(role: 'employee')), isTrue);
    });
    test('admin / super admin / client → not required', () {
      expect(DepartmentGate.isRequired(_p(role: 'admin')), isFalse);
      expect(
          DepartmentGate.isRequired(_p(role: 'admin', superAdmin: true)), isFalse);
      expect(DepartmentGate.isRequired(_p(role: 'client')), isFalse);
    });
    test('no team → not required (handled by pending/onboarding)', () {
      expect(DepartmentGate.isRequired(_p(role: 'employee', teamId: null)), isFalse);
    });
    test('null profile → not required', () {
      expect(DepartmentGate.isRequired(null), isFalse);
    });
  });

  group('isPending / isFailed (fail CLOSED)', () {
    final m = _p(role: 'manager');
    test('loading → pending (held), not failed', () {
      expect(DepartmentGate.isPending(m, DepartmentResolution.loading), isTrue);
      expect(DepartmentGate.isFailed(m, DepartmentResolution.loading), isFalse);
    });
    test('failed (exception OR missing row) → pending AND failed', () {
      expect(DepartmentGate.isPending(m, DepartmentResolution.failed), isTrue);
      expect(DepartmentGate.isFailed(m, DepartmentResolution.failed), isTrue);
    });
    test('resolved → not pending', () {
      expect(DepartmentGate.isPending(m, DepartmentResolution.resolved), isFalse);
    });
    test('admin never held, even on failed', () {
      final a = _p(role: 'admin');
      expect(DepartmentGate.isPending(a, DepartmentResolution.failed), isFalse);
      expect(DepartmentGate.isPending(a, DepartmentResolution.loading), isFalse);
    });
    test('no-team user never held', () {
      final e = _p(role: 'employee', teamId: null);
      expect(DepartmentGate.isPending(e, DepartmentResolution.failed), isFalse);
    });
  });

  group('departmentGateRedirect (no redirect loop)', () {
    test('pending + not on /resolving → /resolving', () {
      expect(
        WorkspaceRouting.departmentGateRedirect('/dashboard', pending: true),
        '/resolving',
      );
      expect(
        WorkspaceRouting.departmentGateRedirect('/calendar', pending: true),
        '/resolving',
      );
    });
    test('pending + already on /resolving → null (no loop)', () {
      expect(
        WorkspaceRouting.departmentGateRedirect('/resolving', pending: true),
        isNull,
      );
    });
    test('not pending → null (normal routing applies)', () {
      expect(
        WorkspaceRouting.departmentGateRedirect('/resolving', pending: false),
        isNull,
      );
    });
  });

  group('end-to-end gate + production decision', () {
    test('Production lookup success → Calendar-only, not held', () {
      final m = _p(role: 'manager');
      expect(DepartmentGate.isPending(m, DepartmentResolution.resolved), isFalse);
      expect(
          _isProductionOnly(m, DepartmentResolution.resolved, Department.production),
          isTrue);
    });

    test('Non-Production success → normal workspace, not held, not production', () {
      final e = _p(role: 'employee');
      expect(DepartmentGate.isPending(e, DepartmentResolution.resolved), isFalse);
      expect(
          _isProductionOnly(e, DepartmentResolution.resolved, Department.marketing),
          isFalse);
    });

    test('Lookup exception / missing row → held, NOT production-only, NOT normal', () {
      final e = _p(role: 'employee');
      // failed → held on /resolving (so neither calendar-only nor full app)
      expect(DepartmentGate.isPending(e, DepartmentResolution.failed), isTrue);
      // and production-only is false while unresolved (so no silent calendar lock
      // either — the gate, not the production flag, is what holds them)
      expect(_isProductionOnly(e, DepartmentResolution.failed, null), isFalse);
    });

    test('Admin / Super Admin / Client unchanged (never held)', () {
      for (final p in [
        _p(role: 'admin'),
        _p(role: 'admin', superAdmin: true),
        _p(role: 'client'),
      ]) {
        expect(DepartmentGate.isPending(p, DepartmentResolution.failed), isFalse);
        expect(_isProductionOnly(p, DepartmentResolution.resolved, Department.production),
            isFalse);
      }
    });

    test('Retry after failure → correct workspace once resolved', () {
      final m = _p(role: 'manager');
      // 1. failed → held
      expect(DepartmentGate.isPending(m, DepartmentResolution.failed), isTrue);
      // 2. retry → loading → still held (no premature exposure)
      expect(DepartmentGate.isPending(m, DepartmentResolution.loading), isTrue);
      // 3a. resolved Production → released to Calendar-only
      expect(DepartmentGate.isPending(m, DepartmentResolution.resolved), isFalse);
      expect(
          _isProductionOnly(m, DepartmentResolution.resolved, Department.production),
          isTrue);
      // 3b. resolved Marketing → released to normal workspace
      expect(
          _isProductionOnly(m, DepartmentResolution.resolved, Department.marketing),
          isFalse);
    });
  });
}
