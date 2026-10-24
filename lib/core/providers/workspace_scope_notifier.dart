// lib/core/providers/workspace_scope_notifier.dart
// Holds the "current department workspace" scope for the signed-in user.
//
// Authorization is derived from the VERIFIED profile (role) and the user's
// loaded team assignment via DepartmentService — never from the department
// catalog alone. This mirrors the DB RLS for the UI; it is NOT itself a
// security boundary (see DEPARTMENT_MIGRATION_ASSESSMENT.md §4 and the
// hardcoded super-admin limitation noted in AuthNotifier).
//
// The pure [WorkspaceScopeState] carries all decision logic so it can be
// unit-tested without Supabase/Flutter; [WorkspaceScopeNotifier] wraps it,
// loads team data, and exposes it to the widget tree.

import 'package:flutter/foundation.dart';

import '../auth/auth_notifier.dart';
import '../constants/departments.dart';
import '../models/profile_model.dart';
import '../models/team_model.dart';
import '../repositories/team_repository.dart';
import '../services/department_service.dart';

/// Immutable snapshot of the workspace scope + all access decisions (pure).
@immutable
class WorkspaceScopeState {
  final ProfileModel? profile;

  /// The user's own team (managers/employees). Resolves their single department.
  final TeamModel? ownTeam;

  /// All active teams (global users) — used to map a department to its team.
  final List<TeamModel> allTeams;

  /// Explicit selection for global users; null means "all departments".
  final Department? selected;

  const WorkspaceScopeState({
    this.profile,
    this.ownTeam,
    this.allTeams = const [],
    this.selected,
  });

  /// Admin / Super Admin reach every department.
  bool get isGlobal => profile != null && DepartmentService.isGlobal(profile!);

  /// Departments this user may open (verified: role + own team).
  List<Department> get authorizedDepartments => profile == null
      ? const <Department>[]
      : DepartmentService.accessibleDepartments(profile!, team: ownTeam);

  /// Whether the user can switch between more than one department.
  bool get canSwitch => authorizedDepartments.length > 1;

  /// Whether the user may reach the company-wide Expenses workspace.
  bool get canAccessExpenses =>
      profile != null && DepartmentService.canAccessExpenses(profile!);

  /// The effective department in view:
  /// - global users: the explicit [selected] (null = all departments);
  /// - scoped users: their single authorized department (if any).
  Department? get effectiveDepartment {
    if (isGlobal) return selected;
    final authorized = authorizedDepartments;
    return authorized.isEmpty ? null : authorized.first;
  }

  /// The team that represents [department], if one exists among [allTeams].
  TeamModel? teamFor(Department department) {
    for (final team in allTeams) {
      if (Departments.fromTeam(team) == department) return team;
    }
    return null;
  }

  /// Id that matches no real team. Used to force an EMPTY task result when a
  /// department workspace is active but its backing team is not (yet) resolved,
  /// so a department view can never silently fall back to "all departments".
  static const String noTeamSentinel = '00000000-0000-0000-0000-000000000000';

  /// The team id that scopes TASK LISTS for the current workspace:
  ///   • null              → show all (a global user explicitly in "All
  ///                          Departments"); this is the ONLY "show everything".
  ///   • a real team id    → a specific department is active and resolved.
  ///   • [noTeamSentinel]  → a department is active but has no resolvable team
  ///                          (teamless department, or teams not loaded yet) →
  ///                          match nothing instead of leaking every department.
  /// Scoped (non-global) users return null here; their lists are scoped by
  /// their own profile team + RLS, not by this selection.
  String? get taskScopeTeamId {
    if (!isGlobal) return null;
    final dept = selected; // null = All Departments (intentional "show all")
    if (dept == null) return null;
    return teamFor(dept)?.id ?? noTeamSentinel;
  }

  /// The real team id a NEWLY created task must belong to for the active
  /// workspace (global user). null = "All Departments" → a company-wide task.
  /// Never returns the sentinel (a task must map to a real team or none).
  String? get activeDepartmentTeamId {
    if (!isGlobal) return null;
    final dept = selected;
    return dept == null ? null : teamFor(dept)?.id;
  }

  /// True when [teamId] is the Montage department team. Works for global users
  /// (via [allTeams]) and scoped users (via [ownTeam]), so Montage-only features
  /// resolve correctly for admins, managers and employees alike.
  bool isMontageTeam(String? teamId) {
    if (teamId == null) return false;
    if (ownTeam != null && ownTeam!.id == teamId) {
      return Departments.fromTeam(ownTeam!) == Department.montage;
    }
    for (final team in allTeams) {
      if (team.id == teamId) return Departments.fromTeam(team) == Department.montage;
    }
    return false;
  }

  /// The department represented by [teamId] (looked up among [allTeams]), or
  /// null when the id is unknown or is not a department team. Used to label the
  /// active-scope header consistently with whatever team actually scopes data.
  Department? departmentForTeamId(String? teamId) {
    if (teamId == null) return null;
    for (final team in allTeams) {
      if (team.id == teamId) return Departments.fromTeam(team);
    }
    return null;
  }

  /// Returns a new state with [department] selected, or null when the user is
  /// not permitted to make that selection (scoped users cannot switch; nobody
  /// may select an unauthorized department). [department] == null selects
  /// "all departments" and is allowed only for global users.
  WorkspaceScopeState? trySelect(Department? department) {
    if (!isGlobal) return null;
    if (department != null && !authorizedDepartments.contains(department)) {
      return null;
    }
    return copyWith(selected: department, clearSelected: department == null);
  }

  WorkspaceScopeState copyWith({
    ProfileModel? profile,
    TeamModel? ownTeam,
    List<TeamModel>? allTeams,
    Department? selected,
    bool clearSelected = false,
  }) => WorkspaceScopeState(
    profile: profile ?? this.profile,
    ownTeam: ownTeam ?? this.ownTeam,
    allTeams: allTeams ?? this.allTeams,
    selected: clearSelected ? null : (selected ?? this.selected),
  );
}

class WorkspaceScopeNotifier extends ChangeNotifier {
  WorkspaceScopeNotifier(this._auth) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthNotifier _auth;
  WorkspaceScopeState _state = const WorkspaceScopeState();
  bool _disposed = false;

  WorkspaceScopeState get state => _state;
  List<Department> get authorizedDepartments => _state.authorizedDepartments;
  Department? get effectiveDepartment => _state.effectiveDepartment;
  bool get canSwitch => _state.canSwitch;
  bool get isGlobal => _state.isGlobal;
  bool get canAccessExpenses => _state.canAccessExpenses;

  /// Scope id for task lists (see [WorkspaceScopeState.taskScopeTeamId]).
  String? get taskScopeTeamId => _state.taskScopeTeamId;

  /// Real team id for creating a task in the active workspace
  /// (see [WorkspaceScopeState.activeDepartmentTeamId]).
  String? get activeDepartmentTeamId => _state.activeDepartmentTeamId;

  /// True when [teamId] is the Montage department team (any role).
  bool isMontageTeam(String? teamId) => _state.isMontageTeam(teamId);

  /// Attempt to switch the selected department. Returns false (and does nothing)
  /// when the selection is not authorized.
  bool select(Department? department) {
    final next = _state.trySelect(department);
    if (next == null) return false;
    _state = next;
    _safeNotify();
    return true;
  }

  void _onAuthChanged() {
    final profile = _auth.profile;
    if (profile == null) {
      _state = const WorkspaceScopeState();
      _safeNotify();
      return;
    }
    // Reset to the new profile immediately (keeps UI responsive), then hydrate
    // team data asynchronously.
    _state = WorkspaceScopeState(profile: profile);
    _safeNotify();
    _hydrate(profile);
  }

  Future<void> _hydrate(ProfileModel profile) async {
    try {
      if (DepartmentService.isGlobal(profile)) {
        final teams = await TeamRepository.fetchAll(activeOnly: true);
        if (_disposed || _auth.profile?.id != profile.id) return;
        _state = _state.copyWith(allTeams: teams);
      } else {
        final team = profile.teamId == null
            ? null
            : await TeamRepository.fetchById(profile.teamId!);
        if (_disposed || _auth.profile?.id != profile.id) return;
        _state = _state.copyWith(ownTeam: team);
      }
      _safeNotify();
    } catch (_) {
      // Non-fatal: scope still works off role; team data simply stays empty.
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
