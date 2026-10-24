// test/department_service_test.dart
// Milestone 1 — proves department/scope resolution for every role, with no
// dependency on Flutter bindings, Supabase, or network.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/models/team_model.dart';
import 'package:task_ora/core/services/department_service.dart';

ProfileModel _profile({
  required String role,
  String? teamId,
  bool superAdmin = false,
}) => ProfileModel(
  id: 'u-$role',
  role: role,
  fullName: 'Test $role',
  status: 'active',
  teamId: teamId,
  timezone: 'UTC',
  preferredLanguage: 'en',
  createdAt: '2026-01-01',
  isSuperAdminFlag: superAdmin,
);

TeamModel _team({required String name, String? department}) => TeamModel(
  id: 't-$name',
  name: name,
  department: department,
  isActive: true,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
);

void main() {
  group('ProfileModel role flags', () {
    test('plain admin is admin + global, not super admin', () {
      final p = _profile(role: 'admin');
      expect(p.isAdmin, isTrue);
      expect(p.isSuperAdmin, isFalse);
    });

    test('super admin flag makes an admin a verified super admin', () {
      final p = _profile(role: 'admin', superAdmin: true);
      expect(p.isSuperAdmin, isTrue);
      expect(p.isAdmin, isTrue);
    });

    test('legacy role string "super_admin" still resolves', () {
      final p = _profile(role: 'super_admin');
      expect(p.isSuperAdmin, isTrue);
      expect(p.isAdmin, isTrue);
    });

    test('manager/employee/client are not admin', () {
      expect(_profile(role: 'manager').isAdmin, isFalse);
      expect(_profile(role: 'employee').isAdmin, isFalse);
      expect(_profile(role: 'client').isAdmin, isFalse);
    });

    test('is_super_admin is read from the map and defaults to false', () {
      final withFlag = ProfileModel.fromMap({
        'id': 'x',
        'role': 'admin',
        'full_name': 'X',
        'status': 'active',
        'timezone': 'UTC',
        'preferred_language': 'en',
        'created_at': '2026-01-01',
        'is_super_admin': true,
      });
      expect(withFlag.isSuperAdmin, isTrue);

      final withoutColumn = ProfileModel.fromMap({
        'id': 'y',
        'role': 'admin',
        'full_name': 'Y',
      });
      expect(withoutColumn.isSuperAdmin, isFalse);
    });
  });

  group('Departments resolution', () {
    test('canonical names resolve', () {
      expect(Departments.fromLabel('Marketing'), Department.marketing);
      expect(Departments.fromLabel('montage'), Department.montage);
      expect(Departments.fromLabel('Studio'), Department.studio);
    });

    test('legacy "Video Production" maps to Production', () {
      expect(Departments.fromLabel('Video Production'), Department.production);
      expect(
        Departments.fromTeam(_team(name: 'Video Production')),
        Department.production,
      );
    });

    test('department field wins over name', () {
      final t = _team(name: 'Anything', department: 'Sales');
      expect(Departments.fromTeam(t), Department.sales);
    });

    test('unknown / internal team resolves to null', () {
      expect(Departments.fromLabel('Admins'), isNull);
      expect(Departments.fromLabel(''), isNull);
      expect(Departments.fromLabel(null), isNull);
      expect(Departments.fromTeam(_team(name: 'Admins')), isNull);
    });
  });

  group('DepartmentService access', () {
    test('admin reaches all departments + expenses', () {
      final p = _profile(role: 'admin');
      expect(DepartmentService.accessibleDepartments(p), Departments.all);
      expect(DepartmentService.canAccessExpenses(p), isTrue);
      expect(DepartmentService.isGlobal(p), isTrue);
    });

    test('super admin reaches all departments + expenses', () {
      final p = _profile(role: 'admin', superAdmin: true);
      expect(DepartmentService.accessibleDepartments(p), Departments.all);
      expect(DepartmentService.canAccessExpenses(p), isTrue);
    });

    test('manager is scoped to own team department, no expenses', () {
      final p = _profile(role: 'manager', teamId: 't1');
      final team = _team(name: 'Marketing');
      expect(DepartmentService.accessibleDepartments(p, team: team), [
        Department.marketing,
      ]);
      expect(DepartmentService.canAccessExpenses(p), isFalse);
      expect(
        DepartmentService.canAccess(p, Department.sales, team: team),
        isFalse,
      );
      expect(
        DepartmentService.canAccess(p, Department.marketing, team: team),
        isTrue,
      );
    });

    test('employee on Video Production team sees Production only', () {
      final p = _profile(role: 'employee', teamId: 't2');
      final team = _team(name: 'Video Production');
      expect(DepartmentService.accessibleDepartments(p, team: team), [
        Department.production,
      ]);
    });

    test('manager on the internal Admins team sees no department', () {
      final p = _profile(role: 'manager', teamId: 't3');
      final team = _team(name: 'Admins');
      expect(DepartmentService.accessibleDepartments(p, team: team), isEmpty);
    });

    test('client sees no departments and no expenses', () {
      final p = _profile(role: 'client');
      expect(DepartmentService.accessibleDepartments(p), isEmpty);
      expect(DepartmentService.canAccessExpenses(p), isFalse);
    });

    test('manager/employee without a loaded team resolves to empty', () {
      expect(
        DepartmentService.accessibleDepartments(_profile(role: 'manager')),
        isEmpty,
      );
    });
  });
}
