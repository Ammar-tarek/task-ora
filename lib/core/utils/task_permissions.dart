// lib/core/utils/task_permissions.dart
// Single source of truth for what each role can see / do on tasks.

import '../models/profile_model.dart';

class TaskPermissions {
  final ProfileModel profile;
  const TaskPermissions(this.profile);

  // ── Data visibility ─────────────────────────────────────────────────────────

  /// Admin + manager see every task; employee sees team/assigned; client sees their own.
  bool get canSeeAllTasks    => profile.isAdminOrManager;

  /// Cost / price visible to admin, manager, and client (to see what they're paying).
  bool get canSeeCost        => profile.isAdminOrManager || profile.isClient;

  /// Internal comments and @mentions visible to internal roles only.
  bool get canSeeComments    => !profile.isClient;

  /// Full edit audit trail — admin and manager only.
  bool get canSeeEditHistory => profile.isAdminOrManager;

  /// Priority hidden from clients (internal concern).
  bool get canSeePriority    => !profile.isClient;

  /// Progress % hidden from clients.
  bool get canSeeProgress    => !profile.isClient;

  /// Assignee list hidden from clients.
  bool get canSeeAssignees   => !profile.isClient;

  /// Description hidden from clients (may contain internal notes).
  bool get canSeeDescription => !profile.isClient;

  // ── Edit abilities ───────────────────────────────────────────────────────────

  /// Admin and manager can edit all task fields (title, desc, priority, cost…).
  bool get canEditFull     => profile.isAdminOrManager;

  /// Employees can change status on tasks they own or are assigned to.
  bool get canEditStatus   => !profile.isClient;

  /// Employees can slide the progress bar on tasks they own or are assigned to.
  bool get canEditProgress => !profile.isClient;

  /// Only admin can edit the "manager-level" fields (reassigning to another
  /// team, changing client, etc.). Manager edits their own team's tasks.
  bool get canEditAdminFields => profile.isAdmin;

  /// Employees and above can add internal comments / mention teammates.
  bool get canAddComment => !profile.isClient;

  // ── Actions ─────────────────────────────────────────────────────────────────

  bool get canCreateTask  => !profile.isClient;
  bool get canDeleteTask  => profile.isAdminOrManager;

  /// Employees can drag tasks to reorder their personal work queue.
  bool get canReorderTasks => !profile.isClient;
}
