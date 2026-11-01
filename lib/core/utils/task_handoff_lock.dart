// lib/core/utils/task_handoff_lock.dart
// UI-facing mirror of the database handoff lock (guard_transferred_task_* +
// handoff_task RPC + tasks_sender_view policy). The DATABASE is the real
// boundary; this only decides what the UI should show/enable so a user isn't
// offered an action the DB will reject.
//
// DIRECT-TRANSFER model (Option A): handoff immediately sets team_id to the
// receiving department and stamps handoffFromTeamId with the sender. There is
// NO pending accept/reject state. A task with a non-null handoffFromTeamId is
// "transferred": its definition is locked to everyone but a global admin, only
// the receiving team (team_id == its current teamId) may track status/progress,
// and only the receiving team's manager may assign it (to its own employees).

import '../models/task_model.dart';

class TaskHandoffLock {
  TaskHandoffLock._();

  /// Transferred to another department (definition locked, receiving-only write).
  static bool isTransferred(TaskModel t) =>
      (t.handoffFromTeamId ?? '').isNotEmpty;

  /// Alias kept for call sites: in the direct model "locked" == "transferred".
  static bool isLocked(TaskModel t) => isTransferred(t);

  /// May the viewer edit DEFINITION fields (title, description, priority, cost,
  /// deadline, client, team, …)? Locked once transferred — only a global admin
  /// overrides. For a normal task this returns true and the usual role
  /// permissions (TaskPermissions) still apply on top.
  static bool canEditDefinition(TaskModel t, {required bool isGlobalAdmin}) {
    if (isTransferred(t)) return isGlobalAdmin;
    return true;
  }

  /// May the viewer track status/progress? On a transferred task only the
  /// CURRENT (receiving) team may — the sending department is view-only. Global
  /// admin overrides. Normal task: true (role perms still apply on top).
  static bool canTrackStatus(
    TaskModel t, {
    String? myTeamId,
    bool isGlobalAdmin = false,
  }) {
    if (isGlobalAdmin) return true;
    if (!isTransferred(t)) return true;
    return myTeamId != null && myTeamId == t.teamId;
  }

  /// May the viewer assign/reassign the task? On a transferred task only the
  /// receiving team's manager may (DB also enforces the assignee belongs to that
  /// team). Global admin overrides. Normal task: true (role perms apply on top).
  static bool canAssign(
    TaskModel t, {
    required bool isManager,
    String? myTeamId,
    required bool isGlobalAdmin,
  }) {
    if (isGlobalAdmin) return true;
    if (!isTransferred(t)) return true;
    return isManager && myTeamId != null && myTeamId == t.teamId;
  }

  /// A transferred task cannot be deleted by a department (admin only).
  static bool canDelete(TaskModel t, {required bool isGlobalAdmin}) =>
      isGlobalAdmin || !isTransferred(t);

  /// A transferred task cannot be re-transferred by a department (admin only).
  static bool canHandoff(TaskModel t, {required bool isGlobalAdmin}) =>
      isGlobalAdmin || !isTransferred(t);
}
