// lib/features/team/team_performance_repository.dart
// Team performance hub data: the authorized member list + a pure task summary.
// All reads run under RLS, so a manager only ever sees their own team and an
// admin sees everyone — the scope is enforced by the database, not here.

import '../../core/models/profile_model.dart';
import '../../core/models/task_model.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/services/supabase_service.dart';

/// One selectable team member.
class TeamMember {
  final String id;
  final String name;
  final String role;
  final String status; // 'active' | 'inactive' | 'suspended'
  final bool isSuperAdmin;
  const TeamMember({
    required this.id,
    required this.name,
    required this.role,
    this.status = 'active',
    this.isSuperAdmin = false,
  });

  bool get isActive => status == 'active';
  bool get isAdmin => role == 'admin' || isSuperAdmin;

  /// Count of active members (used for the active-only Team Size).
  static int activeCount(Iterable<TeamMember> members) =>
      members.where((m) => m.isActive).length;
}

/// Single-bucket task counts for one employee (no double counting).
class EmployeeTaskSummary {
  final int assigned; // total tasks assigned
  final int awaitingAcceptance; // assignment response still pending
  final int inProgress;
  final int awaitingReview; // employee_done
  final int completed; // completed / client_approved
  final int changesRequested; // management sent back (changes_requested/client_rejected)
  final int assignmentRejected; // employee rejected the assignment (distinct!)

  const EmployeeTaskSummary({
    this.assigned = 0,
    this.awaitingAcceptance = 0,
    this.inProgress = 0,
    this.awaitingReview = 0,
    this.completed = 0,
    this.changesRequested = 0,
    this.assignmentRejected = 0,
  });
}

/// A task tagged with the viewed employee's assignment response, for history.
class EmployeeTaskRow {
  final TaskModel task;
  final String? response; // this employee's assignment response
  final String? responseReason;
  const EmployeeTaskRow({required this.task, this.response, this.responseReason});

  /// Single history bucket. Assignment-pending wins first so an unanswered
  /// assignment is never miscounted as "in progress".
  String get bucket {
    if (response == 'pending') return 'awaiting_acceptance';
    switch (task.status) {
      case 'employee_done':
        return 'awaiting_review';
      case 'completed':
      case 'client_approved':
        return 'completed';
      case 'changes_requested':
      case 'client_rejected':
        return 'changes_requested';
      case 'in_progress':
        return 'in_progress';
      default:
        return 'other';
    }
  }
}

/// A past assignment rejection, read from the append-only task_audit_log so it
/// survives the assignee-row delete and any later reassignment.
class AssignmentRejection {
  final String taskTitle;
  final String reason;
  final String at; // created_at ISO
  const AssignmentRejection({required this.taskTitle, required this.reason, required this.at});
}

class TeamPerformanceRepository {
  static final _client = SupabaseService.client;

  /// Assignment rejections by [employeeId] from task_audit_log (durable history).
  /// RLS scopes which tasks' audit rows the viewer may read (admin: all;
  /// manager: own team), so cross-department history never leaks.
  static Future<List<AssignmentRejection>> fetchAssignmentRejections(
    String employeeId,
  ) async {
    try {
      final data = await _client
          .from('task_audit_log')
          .select('created_at, notes, task:tasks(title)')
          .eq('actor_id', employeeId)
          .eq('action', 'assignment_rejected')
          .order('created_at', ascending: false);
      return (data as List).map((m) {
        final map = m as Map<String, dynamic>;
        final t = map['task'] as Map<String, dynamic>?;
        return AssignmentRejection(
          taskTitle: t?['title'] as String? ?? 'Task',
          reason: map['notes'] as String? ?? '',
          at: map['created_at'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Members for the ACTIVE department workspace.
  ///
  /// [scopeTeamId] is the team id of the department the viewer is currently in
  /// (resolved by WorkspaceScopeNotifier):
  ///   • a real team id → only that department's members (admin in a department,
  ///     or a manager — their own team). Excludes null-team users automatically.
  ///   • [WorkspaceScopeState.noTeamSentinel] → a department is active but has
  ///     no backing team → return NOBODY (never fall back to "everyone").
  ///   • null → only a GLOBAL admin in "All Departments" (an explicitly
  ///     org-wide view); scoped users never reach this (they always have a team).
  /// Membership is by `profiles.team_id` — role alone never implies membership,
  /// so an admin/manager from another team is not listed in this department.
  static Future<List<TeamMember>> fetchMembers(
    ProfileModel viewer, {
    String? scopeTeamId,
  }) async {
    // Department active but unresolved team → no members (no global fallback).
    if (scopeTeamId == WorkspaceScopeState.noTeamSentinel) return [];
    try {
      // Include status + super-admin flag so the UI can grey out inactive
      // members and apply the admin/super-admin action rules. Inactive members
      // are intentionally KEPT in the list (shown with an Inactive badge).
      var q = _client
          .from('profiles')
          .select('id, full_name, role, status, is_super_admin')
          .neq('role', 'client');
      if (scopeTeamId != null) {
        // A specific department → exactly its team members.
        q = q.eq('team_id', scopeTeamId);
      } else if (!viewer.isAdmin) {
        // Defense in depth: a non-global viewer with no explicit scope is
        // pinned to their own team; never list everyone.
        if (viewer.teamId == null) return [];
        q = q.eq('team_id', viewer.teamId!);
      }
      // scopeTeamId == null AND viewer.isAdmin → "All Departments" org-wide list.
      final data = await q.order('full_name');
      return (data as List)
          .map((m) => TeamMember(
                id: (m as Map<String, dynamic>)['id'] as String,
                name: m['full_name'] as String? ?? 'Unknown',
                role: m['role'] as String? ?? 'employee',
                status: m['status'] as String? ?? 'active',
                isSuperAdmin: m['is_super_admin'] as bool? ?? false,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // NOTE: the client↔department directory that used client_task_visibility was
  // retired. The single Clients module (ClientsScreen at /department-clients)
  // now scopes clients by client_profiles.client_type, so the old
  // fetchDepartmentClients / fetchAllClients / addClientToDepartment helpers
  // were removed. client_task_visibility is left untouched in the database.

  /// Tag each task with the employee's own assignment response.
  static List<EmployeeTaskRow> rowsFor(List<TaskModel> tasks, String employeeId) {
    return tasks.map((t) {
      final a = t.assigneeFor(employeeId);
      return EmployeeTaskRow(task: t, response: a?.response, responseReason: a?.responseReason);
    }).toList();
  }

  /// Pure, single-bucket summary (unit-tested, no DB).
  static EmployeeTaskSummary summarize(List<EmployeeTaskRow> rows) {
    int awaitingAcceptance = 0,
        inProgress = 0,
        awaitingReview = 0,
        completed = 0,
        changesRequested = 0,
        assignmentRejected = 0;
    for (final r in rows) {
      if (r.response == 'rejected') assignmentRejected++;
      switch (r.bucket) {
        case 'awaiting_acceptance':
          awaitingAcceptance++;
          break;
        case 'in_progress':
          inProgress++;
          break;
        case 'awaiting_review':
          awaitingReview++;
          break;
        case 'completed':
          completed++;
          break;
        case 'changes_requested':
          changesRequested++;
          break;
      }
    }
    return EmployeeTaskSummary(
      assigned: rows.length,
      awaitingAcceptance: awaitingAcceptance,
      inProgress: inProgress,
      awaitingReview: awaitingReview,
      completed: completed,
      changesRequested: changesRequested,
      assignmentRejected: assignmentRejected,
    );
  }
}
