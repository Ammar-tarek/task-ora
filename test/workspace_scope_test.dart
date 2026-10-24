// test/workspace_scope_test.dart
// M2 — workspace scope decisions: switching, unauthorized access, department↔
// team mapping, and client scoping. Targets the pure WorkspaceScopeState.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/models/team_model.dart';
import 'package:task_ora/core/providers/workspace_scope_notifier.dart';

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

TeamModel _t(String name, {String? department}) => TeamModel(
  id: 't-$name',
  name: name,
  department: department,
  isActive: true,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
);

void main() {
  final allTeams = [
    _t('Marketing'),
    _t('Montage'),
    _t('Video Production'),
    _t('Sales'),
    _t('Admins'),
  ];

  group('task scope team id (department isolation guard)', () {
    WorkspaceScopeState global({Department? selected}) => WorkspaceScopeState(
      profile: _p(role: 'admin'),
      allTeams: allTeams,
      selected: selected,
    );

    test('All Departments → null (the only "show all")', () {
      expect(global().taskScopeTeamId, isNull);
    });

    test('a resolved department → its real team id (not null)', () {
      final s = global(selected: Department.marketing);
      expect(s.taskScopeTeamId, 't-Marketing');
      expect(s.taskScopeTeamId, isNot(WorkspaceScopeState.noTeamSentinel));
    });

    test('active department with NO backing team → sentinel, never null', () {
      // Studio has no team row → must match nothing, not leak every department.
      final s = global(selected: Department.studio);
      expect(s.taskScopeTeamId, WorkspaceScopeState.noTeamSentinel);
      expect(s.taskScopeTeamId, isNotNull);
    });

    test('teams not loaded yet → sentinel, never null (no leak on race)', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'admin'),
        allTeams: const [],
        selected: Department.marketing,
      );
      expect(s.taskScopeTeamId, WorkspaceScopeState.noTeamSentinel);
    });

    test('create uses real team id, never the sentinel', () {
      expect(
        global(selected: Department.marketing).activeDepartmentTeamId,
        't-Marketing',
      );
      expect(global().activeDepartmentTeamId, isNull); // All Departments
      // Teamless department → null (no bogus FK), not the sentinel.
      expect(
        global(selected: Department.studio).activeDepartmentTeamId,
        isNull,
      );
    });

    test('scoped (non-global) user never drives task scope here', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'manager', teamId: 't-Marketing'),
        ownTeam: _t('Marketing'),
      );
      expect(s.taskScopeTeamId, isNull);
      expect(s.activeDepartmentTeamId, isNull);
    });
  });

  group('global (admin / super admin) scope', () {
    test('admin can access all departments and switch', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'admin'),
        allTeams: allTeams,
      );
      expect(s.isGlobal, isTrue);
      expect(s.authorizedDepartments, Departments.all);
      expect(s.canSwitch, isTrue);
      expect(s.canAccessExpenses, isTrue);
      expect(s.effectiveDepartment, isNull); // defaults to "all"
    });

    test('selecting a department updates the effective scope', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'admin'),
        allTeams: allTeams,
      );
      final next = s.trySelect(Department.marketing);
      expect(next, isNotNull);
      expect(next!.effectiveDepartment, Department.marketing);
      // Switch back to all departments.
      expect(next.trySelect(null)!.effectiveDepartment, isNull);
    });

    test('super admin flag grants global scope too', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'admin', superAdmin: true),
        allTeams: allTeams,
      );
      expect(s.isGlobal, isTrue);
      expect(s.authorizedDepartments, Departments.all);
    });

    test('department maps to its team (Video Production → Production)', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'admin'),
        allTeams: allTeams,
      );
      expect(s.teamFor(Department.production)?.name, 'Video Production');
      expect(s.teamFor(Department.marketing)?.name, 'Marketing');
      expect(s.teamFor(Department.studio), isNull); // no Studio team yet
    });
  });

  group('scoped (manager / employee) access', () {
    test('manager is locked to their own department and cannot switch', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'manager', teamId: 't1'),
        ownTeam: _t('Marketing'),
      );
      expect(s.isGlobal, isFalse);
      expect(s.authorizedDepartments, [Department.marketing]);
      expect(s.canSwitch, isFalse);
      expect(s.effectiveDepartment, Department.marketing);
      expect(s.canAccessExpenses, isFalse);
    });

    test('unauthorized department access is refused', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'manager', teamId: 't1'),
        ownTeam: _t('Marketing'),
      );
      // A scoped user cannot switch at all.
      expect(s.trySelect(Department.sales), isNull);
      expect(s.trySelect(Department.marketing), isNull);
      // And has no authorization for other departments.
      expect(s.authorizedDepartments.contains(Department.sales), isFalse);
    });

    test('employee on Video Production is scoped to Production', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'employee', teamId: 't2'),
        ownTeam: _t('Video Production'),
      );
      expect(s.authorizedDepartments, [Department.production]);
      expect(s.effectiveDepartment, Department.production);
    });

    test('member of the internal Admins team has no department workspace', () {
      final s = WorkspaceScopeState(
        profile: _p(role: 'manager', teamId: 't3'),
        ownTeam: _t('Admins'),
      );
      expect(s.authorizedDepartments, isEmpty);
      expect(s.effectiveDepartment, isNull);
    });
  });

  group('client scope', () {
    test('client has no departments, no expenses, cannot switch', () {
      final s = WorkspaceScopeState(profile: _p(role: 'client'));
      expect(s.authorizedDepartments, isEmpty);
      expect(s.canAccessExpenses, isFalse);
      expect(s.canSwitch, isFalse);
      expect(s.trySelect(Department.marketing), isNull);
    });
  });

  group('empty / unloaded', () {
    test('no profile yields an empty scope', () {
      const s = WorkspaceScopeState();
      expect(s.isGlobal, isFalse);
      expect(s.authorizedDepartments, isEmpty);
      expect(s.effectiveDepartment, isNull);
    });
  });

  // Mirrors the REAL teams after the department migration: Sales has a NULL
  // `department` (resolved by name) and Production is backed by the legacy
  // "Video Production" team. Guards calendar/task admin department scoping.
  group('real department topology (post-migration)', () {
    final realTeams = [
      _t('Marketing', department: 'Marketing'),
      _t('Montage', department: 'Montage'),
      _t('Video Production', department: 'Video Production'),
      _t('Sales'), // department intentionally NULL — must resolve by name
      _t('Studio', department: 'Studio'),
      _t('Admins'), // internal — not a department workspace
    ];
    WorkspaceScopeState global({Department? selected}) => WorkspaceScopeState(
      profile: _p(role: 'admin'),
      allTeams: realTeams,
      selected: selected,
    );

    test('every one of the five departments resolves to its real team', () {
      final s = global();
      expect(s.teamFor(Department.marketing)?.name, 'Marketing');
      expect(s.teamFor(Department.montage)?.name, 'Montage');
      expect(s.teamFor(Department.production)?.name, 'Video Production');
      expect(s.teamFor(Department.sales)?.name, 'Sales'); // null department
      expect(s.teamFor(Department.studio)?.name, 'Studio');
    });

    test(
      'admin switching scopes to a real team id for all five (no sentinel)',
      () {
        for (final dept in Departments.all) {
          final id = global(selected: dept).taskScopeTeamId;
          expect(id, 't-${global(selected: dept).teamFor(dept)!.name}');
          expect(id, isNot(WorkspaceScopeState.noTeamSentinel));
          expect(id, isNotNull);
        }
      },
    );

    test('Sales (null department) still maps back from its team id', () {
      expect(global().departmentForTeamId('t-Sales'), Department.sales);
      expect(
        global().departmentForTeamId('t-Video Production'),
        Department.production,
      );
      expect(global().departmentForTeamId('t-Studio'), Department.studio);
    });
  });

  group('active-scope header label (departmentForTeamId)', () {
    final s = WorkspaceScopeState(
      profile: _p(role: 'admin'),
      allTeams: allTeams,
    );

    test('null team id = All Departments (no department)', () {
      expect(s.departmentForTeamId(null), isNull);
    });

    test('a department team id resolves to its department', () {
      expect(s.departmentForTeamId('t-Marketing'), Department.marketing);
      expect(
        s.departmentForTeamId('t-Video Production'),
        Department.production,
      );
    });

    test('the internal Admins team id resolves to no department', () {
      expect(s.departmentForTeamId('t-Admins'), isNull);
    });

    test('an unknown team id resolves to null', () {
      expect(s.departmentForTeamId('does-not-exist'), isNull);
    });
  });
}
