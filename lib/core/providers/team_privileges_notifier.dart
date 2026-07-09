// lib/core/providers/team_privileges_notifier.dart
// Resolves the EFFECTIVE privileges for the currently-logged-in user.
// Priority: per-user override (user_privileges) → team default (team_privileges)
// → hard-coded default. Screens watch the boolean getters to gate actions.

import 'package:flutter/foundation.dart';
import '../auth/auth_notifier.dart';
import '../models/team_privileges_model.dart';
import '../models/user_privileges_model.dart';
import '../repositories/team_privileges_repository.dart';
import '../repositories/user_privileges_repository.dart';

class TeamPrivilegesNotifier extends ChangeNotifier {
  final AuthNotifier _auth;
  TeamPrivilegesModel? _teamPrivileges;
  UserPrivilegesModel? _userPrivileges;

  TeamPrivilegesNotifier(this._auth) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  TeamPrivilegesModel? get privileges => _teamPrivileges;

  bool get _isManager => _auth.profile?.isManager == true;

  /// Resolve an effective capability:
  ///  1. explicit per-user override wins
  ///  2. then the team default (managers)
  ///  3. otherwise: managers get [managerDefault]; everyone else gets false
  ///     (an employee has no management powers unless explicitly granted).
  bool _resolve(bool? user, bool? team, bool managerDefault) {
    if (user != null) return user;
    if (team != null) return team;
    return _isManager ? managerDefault : false;
  }

  // ── Effective gating getters — per-user overrides team, then role default ──
  // Admin always bypasses all checks (callers do `isAdmin || canX`).
  bool get canManageAttendance => _resolve(
      _userPrivileges?.canManageAttendance, _teamPrivileges?.canManageAttendance, true);
  bool get canManageExpenses => _resolve(
      _userPrivileges?.canManageExpenses, _teamPrivileges?.canManageExpenses, true);
  bool get canManageTasks => _resolve(
      _userPrivileges?.canManageTasks, _teamPrivileges?.canManageTasks, true);
  bool get canManagePenalties => _resolve(
      _userPrivileges?.canManagePenalties, _teamPrivileges?.canManagePenalties, true);
  bool get canManageClients => _resolve(
      _userPrivileges?.canManageClients, _teamPrivileges?.canManageClients, true);
  bool get canCreateEmployees => _resolve(
      _userPrivileges?.canCreateEmployees, _teamPrivileges?.canCreateEmployees, true);
  bool get canViewFinance => _resolve(
      _userPrivileges?.canViewFinance, _teamPrivileges?.canViewFinance, false);

  void _onAuthChanged() {
    final profile = _auth.profile;
    if (profile == null) {
      _teamPrivileges = null;
      _userPrivileges = null;
      notifyListeners();
      return;
    }
    _load(profile.id, profile.teamId, profile.isManager);
  }

  Future<void> _load(String userId, String? teamId, bool isManager) async {
    // Team default only applies to managers with a team.
    try {
      _teamPrivileges = (isManager && teamId != null)
          ? await TeamPrivilegesRepository.fetchForTeam(teamId)
          : null;
    } catch (_) {
      _teamPrivileges = null;
    }
    // Per-user override applies to anyone.
    _userPrivileges = await UserPrivilegesRepository.fetchForUser(userId);
    notifyListeners();
  }

  /// Re-fetch privileges for the current user (call after edits).
  Future<void> reload() async {
    final profile = _auth.profile;
    if (profile != null) {
      await _load(profile.id, profile.teamId, profile.isManager);
    }
  }
}
