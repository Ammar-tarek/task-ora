// test/revenue_department_isolation_test.dart
// The revenue sheet loads rows scoped by WorkspaceScopeState.taskScopeTeamId
// (the same guard the task lists use). This pins the isolation contract the
// sheet depends on so one department can never silently see another's revenue:
//   • All Departments            → null  (admin explicitly views everything)
//   • a resolved department      → that department's real team id
//   • a department with no team  → the no-team sentinel → matches nothing
// The database RLS remains the real boundary; this covers the UI scoping.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
import 'package:task_ora/core/models/profile_model.dart';
import 'package:task_ora/core/models/team_model.dart';
import 'package:task_ora/core/providers/workspace_scope_notifier.dart';

ProfileModel _admin() => ProfileModel(
  id: 'admin',
  role: 'admin',
  fullName: 'Admin',
  status: 'active',
  timezone: 'UTC',
  preferredLanguage: 'en',
  createdAt: '2026-01-01',
);

TeamModel _t(String name) => TeamModel(
  id: 't-$name',
  name: name,
  isActive: true,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
);

void main() {
  final allTeams = [_t('Marketing'), _t('Montage'), _t('Sales')];

  WorkspaceScopeState scope({Department? selected, List<TeamModel>? teams}) =>
      WorkspaceScopeState(
        profile: _admin(),
        allTeams: teams ?? allTeams,
        selected: selected,
      );

  test('All Departments shows everything (null scope)', () {
    expect(scope().taskScopeTeamId, isNull);
  });

  test('a specific department scopes to its own team id', () {
    expect(scope(selected: Department.marketing).taskScopeTeamId, 't-Marketing');
  });

  test('a specific department never leaks as "all" (never null)', () {
    expect(scope(selected: Department.sales).taskScopeTeamId, isNotNull);
  });

  test('a department with no backing team matches nothing (sentinel)', () {
    // Montage selected but not present among the loaded teams → sentinel.
    final s = scope(selected: Department.montage, teams: [_t('Marketing')]);
    expect(s.taskScopeTeamId, WorkspaceScopeState.noTeamSentinel);
  });
}
