// lib/core/repositories/task_repository.dart
// All Supabase queries related to tasks, boards, columns, assignees,
// comments, and edit history.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/profile_model.dart';
import '../services/supabase_service.dart';
import 'notification_repository.dart';
import 'team_repository.dart';

import 'app_settings_repository.dart';

class TaskRepository {
  static final _client = SupabaseService.client;
  static final _adminClient = SupabaseService.adminClient;

  // ── Task select fragment (reused across methods) ────────────────────────────
  static const _taskSelect =
      '*, client:client_profiles(company_name), task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name))';

  // ═══════════════════════════════════════════════════════════════════════════
  // Role-aware fetch (primary entry point)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetch tasks visible to [profile] according to role:
  ///   admin / manager → all tasks (manager scoped to their team)
  ///   employee        → team tasks + tasks they are assigned to
  ///   client          → tasks where client_id = profile.id
  ///
  /// [overrideTeamId] is admin-only: forces a team filter on top of the
  /// normal "all" admin view (used by the admin team-switcher UI).
  static Future<List<TaskModel>> fetchTasksForProfile(
    ProfileModel profile, {
    String? overrideTeamId,
  }) async {
    List<TaskModel> tasks = [];
    if (profile.isAdminOrManager) {
      final teamId =
          overrideTeamId ?? (profile.isManager ? profile.teamId : null);
      tasks = await _fetchAll(teamId: teamId);
    } else if (profile.isEmployee) {
      tasks = await _fetchEmployeeTasks(profile);
    } else if (profile.isClient) {
      tasks = await _fetchClientTasks(profile);
    }

    if (!profile.isAdmin) {
      tasks.removeWhere((t) => t.isArchived);
    }

    if (!profile.isSuperAdmin) {
      final cutoff = await AppSettingsRepository.getWorkDataCutoffDate();
      if (cutoff != null && cutoff.trim().isNotEmpty) {
        final cutoffDt = DateTime.tryParse(cutoff);
        if (cutoffDt != null) {
          tasks.removeWhere((t) {
            final dtStr = t.createdAt;
            final dt = DateTime.tryParse(dtStr.length >= 10 ? dtStr.substring(0, 10) : dtStr);
            if (dt == null) return false;
            return dt.isBefore(cutoffDt);
          });
        }
      }
    }

    return tasks;
  }

  /// Super Admin manual archive operation:
  /// Archives all completed tasks (`status = 'completed'` and `is_archived = false`).
  /// Stores timestamp and archived_by profile ID.
  /// Idempotent operation — skips tasks already archived.
  static Future<Map<String, dynamic>> archiveCompletedTasks({
    required String superAdminId,
  }) async {
    final now = DateTime.now().toIso8601String();

    try {
      // 1. Fetch unarchived completed tasks
      final unarchivedRes = await _adminClient
          .from('tasks')
          .select('id')
          .eq('status', 'completed')
          .or('is_archived.is.null,is_archived.eq.false');

      final unarchivedList = unarchivedRes as List<dynamic>? ?? [];
      final totalToArchive = unarchivedList.length;

      // 2. Fetch already archived completed tasks (for summary count)
      final alreadyArchivedRes = await _adminClient
          .from('tasks')
          .select('id')
          .eq('status', 'completed')
          .eq('is_archived', true);

      final skippedCount = (alreadyArchivedRes as List<dynamic>? ?? []).length;

      if (totalToArchive > 0) {
        final idsToArchive =
            unarchivedList.map((t) => t['id'] as String).toList();
        await _adminClient
            .from('tasks')
            .update({
              'is_archived': true,
              'archived_at': now,
              'archived_by': superAdminId,
              'updated_at': now,
            })
            .inFilter('id', idsToArchive);
      }

      return {
        'archivedCount': totalToArchive,
        'skippedCount': skippedCount,
        'timestamp': now,
        'error': null,
      };
    } catch (e) {
      return {
        'archivedCount': 0,
        'skippedCount': 0,
        'timestamp': now,
        'error': e.toString(),
      };
    }
  }

  /// Selective archive a single task regardless of status.
  static Future<bool> archiveTask(String taskId, {required String profileId}) async {
    final now = DateTime.now().toIso8601String();
    try {
      await _adminClient
          .from('tasks')
          .update({
            'is_archived': true,
            'archived_at': now,
            'archived_by': profileId,
            'updated_at': now,
          })
          .eq('id', taskId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Batch archive multiple tasks by IDs regardless of status.
  static Future<bool> archiveMultipleTasks(
    List<String> taskIds, {
    required String profileId,
  }) async {
    if (taskIds.isEmpty) return true;
    final now = DateTime.now().toIso8601String();
    try {
      // Chunk into batches of 500 for safety with large lists
      for (var i = 0; i < taskIds.length; i += 500) {
        final chunk = taskIds.sublist(
          i,
          (i + 500 > taskIds.length) ? taskIds.length : i + 500,
        );
        await _adminClient
            .from('tasks')
            .update({
              'is_archived': true,
              'archived_at': now,
              'archived_by': profileId,
              'updated_at': now,
            })
            .inFilter('id', chunk);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Count unarchived tasks matching date range and status criteria.
  static Future<int> countUnarchivedTasks({
    DateTime? startDate,
    DateTime? endDate,
    String? statusFilter,
  }) async {
    try {
      dynamic query = _adminClient
          .from('tasks')
          .select('id')
          .or('is_archived.is.null,is_archived.eq.false');

      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      if (startDate != null) {
        final startIso = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0).toIso8601String();
        query = query.gte('created_at', startIso);
      }

      if (endDate != null) {
        final endIso = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59).toIso8601String();
        query = query.lte('created_at', endIso);
      }

      final res = await query;
      return (res as List<dynamic>? ?? []).length;
    } catch (_) {
      return 0;
    }
  }

  /// Super Admin manual archive operation by date range and optional status filter.
  static Future<Map<String, dynamic>> archiveTasksByFilter({
    required String superAdminId,
    DateTime? startDate,
    DateTime? endDate,
    String? statusFilter,
  }) async {
    final now = DateTime.now().toIso8601String();

    try {
      dynamic query = _adminClient
          .from('tasks')
          .select('id')
          .or('is_archived.is.null,is_archived.eq.false');

      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      if (startDate != null) {
        final startIso = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0).toIso8601String();
        query = query.gte('created_at', startIso);
      }

      if (endDate != null) {
        final endIso = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59).toIso8601String();
        query = query.lte('created_at', endIso);
      }

      final unarchivedRes = await query;
      final unarchivedList = unarchivedRes as List<dynamic>? ?? [];
      final totalToArchive = unarchivedList.length;

      if (totalToArchive > 0) {
        final idsToArchive =
            unarchivedList.map((t) => t['id'] as String).toList();
        for (var i = 0; i < idsToArchive.length; i += 500) {
          final chunk = idsToArchive.sublist(
            i,
            (i + 500 > idsToArchive.length) ? idsToArchive.length : i + 500,
          );
          await _adminClient
              .from('tasks')
              .update({
                'is_archived': true,
                'archived_at': now,
                'archived_by': superAdminId,
                'updated_at': now,
              })
              .inFilter('id', chunk);
        }
      }

      return {
        'archivedCount': totalToArchive,
        'timestamp': now,
        'error': null,
      };
    } catch (e) {
      return {
        'archivedCount': 0,
        'timestamp': now,
        'error': e.toString(),
      };
    }
  }

  /// Retrieve / unarchive one or more tasks back to active task views.
  static Future<bool> unarchiveTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return true;
    final now = DateTime.now().toIso8601String();
    try {
      await _adminClient
          .from('tasks')
          .update({
            'is_archived': false,
            'archived_at': null,
            'archived_by': null,
            'updated_at': now,
          })
          .inFilter('id', taskIds);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetch all archived tasks (where is_archived = true).
  static Future<List<TaskModel>> fetchArchivedTasks() async {
    try {
      final data = await _adminClient
          .from('tasks')
          .select(_taskSelect)
          .eq('is_archived', true)
          .order('archived_at', ascending: false);
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        final data = await _adminClient
            .from('tasks')
            .select('*')
            .eq('is_archived', true)
            .order('created_at', ascending: false);
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<List<TaskModel>> _fetchAll({String? teamId}) async {
    // Manager view: own team tasks PLUS tasks handed off to their team (waiting list).
    try {
      final base = _client.from('tasks').select(_taskSelect);
      final query = teamId != null
          ? base
                .or('team_id.eq.$teamId,handoff_to_team_id.eq.$teamId')
                .order('created_at', ascending: false)
          : base.order('created_at', ascending: false);
      final data = await query;
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        final base = _client.from('tasks').select('*');
        final query = teamId != null
            ? base
                  .or('team_id.eq.$teamId,handoff_to_team_id.eq.$teamId')
                  .order('created_at', ascending: false)
            : base.order('created_at', ascending: false);
        final data = await query;
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  // ── Department handoff (waiting list) ───────────────────────────────────────

  /// Manager sends a task to another department. Detaches it from the source
  /// team so no employee sees it; only the target department's manager sees it
  /// in their Waiting List until they accept it.
  static Future<void> handoffTask({
    required String taskId,
    required String fromTeamId,
    required String toTeamId,
    required String byProfileId,
    String? note,
  }) async {
    await _adminClient
        .from('tasks')
        .update({
          'team_id': null,
          'handoff_from_team_id': fromTeamId,
          'handoff_to_team_id': toTeamId,
          'handoff_by': byProfileId,
          'handoff_note': note,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', taskId);
    // Remove old assignees — new department will reassign.
    await _adminClient.from('task_assignees').delete().eq('task_id', taskId);

    // Send notifications to target & source team leads, managers, and admins
    try {
      final taskData = await fetchTaskDetail(taskId);
      final title = taskData?['title'] as String? ?? 'Task';
      final toTeam = await TeamRepository.fetchById(toTeamId);
      final recipients = <String>{};

      if (toTeam?.teamLeadId != null) {
        recipients.add(toTeam!.teamLeadId!);
      }

      final targetManagers = await _adminClient
          .from('profiles')
          .select('id')
          .eq('team_id', toTeamId)
          .eq('role', 'manager');
      for (final row in (targetManagers as List)) {
        recipients.add(row['id'] as String);
      }

      final fromTeam = await TeamRepository.fetchById(fromTeamId);
      if (fromTeam?.teamLeadId != null) {
        recipients.add(fromTeam!.teamLeadId!);
      }
      final sourceManagers = await _adminClient
          .from('profiles')
          .select('id')
          .eq('team_id', fromTeamId)
          .eq('role', 'manager');
      for (final row in (sourceManagers as List)) {
        recipients.add(row['id'] as String);
      }

      final adminRows = await _adminClient
          .from('profiles')
          .select('id')
          .eq('role', 'admin');
      for (final row in (adminRows as List)) {
        recipients.add(row['id'] as String);
      }

      for (final recipientId in recipients) {
        await NotificationRepository.createNotification(
          recipientId: recipientId,
          type: 'task_handoff',
          title: 'Department Task Switch',
          body:
              'Task "$title" has been moved to ${toTeam?.name ?? "another department"}.',
          referenceType: 'task',
          referenceId: taskId,
        );
      }
    } catch (_) {}
  }

  /// Target manager accepts a handoff into their department. The task becomes a
  /// normal team task visible to that team.
  static Future<void> acceptHandoff({
    required String taskId,
    required String teamId,
  }) async {
    // 1. Fetch task details BEFORE clearing handoff_to_team_id
    final taskData = await fetchTaskDetail(taskId);
    final title = taskData?['title'] as String? ?? 'Task';
    final fromTeamId = taskData?['handoff_from_team_id'] as String?;

    await _adminClient
        .from('tasks')
        .update({
          'team_id': teamId,
          'handoff_to_team_id': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', taskId);

    // 2. Notify source & target managers, leads, and admins that handoff was accepted
    try {
      final toTeam = await TeamRepository.fetchById(teamId);
      final recipients = <String>{};

      if (toTeam?.teamLeadId != null) {
        recipients.add(toTeam!.teamLeadId!);
      }

      final targetManagers = await _adminClient
          .from('profiles')
          .select('id')
          .eq('team_id', teamId)
          .eq('role', 'manager');
      for (final row in (targetManagers as List)) {
        recipients.add(row['id'] as String);
      }

      if (fromTeamId != null) {
        final fromTeam = await TeamRepository.fetchById(fromTeamId);
        if (fromTeam?.teamLeadId != null) {
          recipients.add(fromTeam!.teamLeadId!);
        }
        final sourceManagers = await _adminClient
            .from('profiles')
            .select('id')
            .eq('team_id', fromTeamId)
            .eq('role', 'manager');
        for (final row in (sourceManagers as List)) {
          recipients.add(row['id'] as String);
        }
      }

      final adminRows = await _adminClient
          .from('profiles')
          .select('id')
          .eq('role', 'admin');
      for (final row in (adminRows as List)) {
        recipients.add(row['id'] as String);
      }

      for (final recipientId in recipients) {
        await NotificationRepository.createNotification(
          recipientId: recipientId,
          type: 'handoff_accepted',
          title: 'Department Switch Accepted',
          body:
              'Task "$title" handoff was accepted into ${toTeam?.name ?? "target"} department.',
          referenceType: 'task',
          referenceId: taskId,
        );
      }
    } catch (_) {}
  }

  static Future<List<TaskModel>> _fetchEmployeeTasks(
    ProfileModel profile,
  ) async {
    // Employees see ONLY tasks explicitly assigned to them — never all team
    // tasks. A moved task stays hidden until the manager assigns them.
    try {
      final assigneeRows = await _adminClient
          .from('task_assignees')
          .select('task_id')
          .eq('profile_id', profile.id);

      final ids = (assigneeRows as List)
          .map((r) => r['task_id'] as String)
          .toList();
      if (ids.isEmpty) return [];

      final data = await _adminClient
          .from('tasks')
          .select(_taskSelect)
          .inFilter('id', ids)
          .order('created_at', ascending: false);
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<TaskModel>> _fetchClientTasks(ProfileModel profile) async {
    try {
      final data = await _adminClient
          .from('tasks')
          .select(_taskSelect)
          .eq('client_id', profile.id)
          .order('created_at', ascending: false);
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        final data = await _adminClient
            .from('tasks')
            .select('*')
            .eq('client_id', profile.id)
            .order('created_at', ascending: false);
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Legacy fetch (kept for backward compat — prefer fetchTasksForProfile)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<TaskModel>> fetchTasks({
    String? userId,
    String? teamId,
  }) async {
    try {
      final base = _client.from('tasks').select(_taskSelect);
      dynamic query;
      if (userId != null) {
        query = base
            .eq('created_by', userId)
            .order('created_at', ascending: false);
      } else if (teamId != null) {
        query = base
            .eq('team_id', teamId)
            .order('created_at', ascending: false);
      } else {
        query = base.order('created_at', ascending: false);
      }
      final data = await query;
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        final base = _client.from('tasks').select('*');
        dynamic query;
        if (userId != null) {
          query = base
              .eq('created_by', userId)
              .order('created_at', ascending: false);
        } else if (teamId != null) {
          query = base
              .eq('team_id', teamId)
              .order('created_at', ascending: false);
        } else {
          query = base.order('created_at', ascending: false);
        }
        final data = await query;
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<Map<String, List<TaskModel>>> fetchKanbanTasks({
    String? userId,
    String? teamId,
  }) async {
    final tasks = await fetchTasks(userId: userId, teamId: teamId);
    return {
      'not_started': tasks.where((t) => t.status == 'not_started').toList(),
      'in_progress': tasks.where((t) => t.status == 'in_progress').toList(),
      'employee_done': tasks.where((t) => t.status == 'employee_done').toList(),
      'client_approved': tasks
          .where((t) => t.status == 'client_approved')
          .toList(),
      'client_rejected': tasks
          .where((t) => t.status == 'client_rejected')
          .toList(),
      'completed': tasks.where((t) => t.status == 'completed').toList(),
      'on_hold': tasks.where((t) => t.status == 'on_hold').toList(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Task detail — full join
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> fetchTaskDetail(String taskId) async {
    // Level 1 — full join (all optional tables)
    try {
      final data = await _client
          .from('tasks')
          .select('''
            *,
            task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name, avatar_url)),
            task_comments(id, content, is_internal, created_at, author:profiles(full_name)),
            task_attachments(id, file_name, file_url, file_type, is_client_visible),
            task_approvals(id, employee_done_at, client_decision, client_reviewed_at)
          ''')
          .eq('id', taskId)
          .single();
      return data;
    } catch (_) {}

    // Level 2 — assignees + comments (most commonly present tables)
    try {
      final data = await _client
          .from('tasks')
          .select('''
            *,
            task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name, avatar_url)),
            task_comments(id, content, is_internal, created_at, author:profiles(full_name))
          ''')
          .eq('id', taskId)
          .single();
      return data;
    } catch (_) {}

    // Level 3 — assignees only
    try {
      final data = await _client
          .from('tasks')
          .select(
            '*, task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name, avatar_url))',
          )
          .eq('id', taskId)
          .single();
      return data;
    } catch (_) {}

    // Level 4 — bare task row
    try {
      return await _client.from('tasks').select('*').eq('id', taskId).single();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Edit history
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetch the last 20 edits for [taskId].
  /// Silently returns [] if the task_edit_logs table does not exist yet.
  static Future<List<TaskEditLog>> fetchEditHistory(String taskId) async {
    try {
      final data = await _client
          .from('task_audit_log')
          .select('*, actor:profiles!actor_id(full_name)')
          .eq('task_id', taskId)
          .order('created_at', ascending: false)
          .limit(20);
      return (data as List)
          .map((m) => TaskEditLog.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Insert one row into task_edit_logs.
  /// Fire-and-forget: errors are swallowed so that a missing table never
  /// blocks a legitimate task save.
  static Future<void> logTaskEdit(
    String taskId,
    String editedBy,
    String summary,
  ) async {
    try {
      await _client.from('task_audit_log').insert({
        'task_id': taskId,
        'actor_id': editedBy,
        'action': 'edit',
        'notes': summary,
      });
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Comments
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<TaskComment>> fetchComments(String taskId) async {
    try {
      final data = await _client
          .from('task_comments')
          .select(
            'id, content, is_internal, created_at, author:profiles(full_name)',
          )
          .eq('task_id', taskId)
          .order('created_at', ascending: true);
      return (data as List)
          .map((m) => TaskComment.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> addComment(
    String taskId,
    String authorId,
    String content, {
    bool isInternal = true,
  }) async {
    try {
      await _client.from('task_comments').insert({
        'task_id': taskId,
        'author_id': authorId,
        'content': content,
        'is_internal': isInternal,
      });

      try {
        final taskData = await fetchTaskDetail(taskId);
        if (taskData != null) {
          final title = taskData['title'] as String? ?? 'Task';
          final teamId = taskData['team_id'] as String?;
          final assignees = taskData['assignees'] as List? ?? [];
          final assigneeIds = assignees.map((a) => a['id'] as String).toList();

          final authorData = await _client
              .from('profiles')
              .select('full_name')
              .eq('id', authorId)
              .maybeSingle();
          final authorName = authorData?['full_name'] as String? ?? 'A user';
          final preview = content.length > 50 ? '${content.substring(0, 50)}…' : content;

          await NotificationRepository.notifyAction(
            title: 'New Comment on "$title"',
            body: '$authorName: $preview',
            type: 'task_comment',
            referenceType: 'task',
            referenceId: taskId,
            teamId: teamId,
            targetUserIds: assigneeIds,
            actorId: authorId,
          );
        }
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CRUD helpers
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> updateTaskStatus(String taskId, String newStatus, {String? updatedBy}) async {
    try {
      await _client
          .from('tasks')
          .update({'status': newStatus})
          .eq('id', taskId);

      try {
        final taskData = await fetchTaskDetail(taskId);
        if (taskData != null) {
          final title = taskData['title'] as String? ?? 'Task';
          final teamId = taskData['team_id'] as String?;
          final assignees = taskData['assignees'] as List? ?? [];
          final assigneeIds = assignees.map((a) => a['id'] as String).toList();

          await NotificationRepository.notifyAction(
            title: 'Task Status Updated',
            body: 'Task "$title" status changed to "$newStatus".',
            type: 'task_status_changed',
            referenceType: 'task',
            referenceId: taskId,
            teamId: teamId,
            targetUserIds: assigneeIds,
            actorId: updatedBy,
          );
        }
      } catch (_) {}
    } on PostgrestException catch (e) {
      throw Exception('Status update failed [${e.code}]: ${e.message}');
    }
  }

  static Future<void> updateTaskProgress(String taskId, int pct) async {
    await _client
        .from('tasks')
        .update({'completion_percentage': pct})
        .eq('id', taskId);
  }

  static Future<String?> createTask({
    required String title,
    required String createdBy,
    String? teamId,
    String? clientId,
    String? description,
    String priority = 'medium',
    String? dueDate,
  }) async {
    try {
      final result = await _client
          .from('tasks')
          .insert({
            'title': title,
            'created_by': createdBy,
            'team_id': teamId,
            'client_id': clientId,
            'description': description,
            'priority': priority,
            'due_date': dueDate,
            'status': 'not_started',
          })
          .select('id')
          .single();
      final taskId = result['id'] as String;

      try {
        await NotificationRepository.notifyAction(
          title: 'New Task Created',
          body: 'Task "$title" has been created.',
          type: 'task_created',
          referenceType: 'task',
          referenceId: taskId,
          teamId: teamId,
          actorId: createdBy,
        );
      } catch (_) {}

      return taskId;
    } catch (_) {
      return null;
    }
  }

  /// Update task fields and optionally log the edit.
  /// Pass [editedBy] + [editSummary] to record who changed what.
  static Future<bool> updateTask({
    required String id,
    required String title,
    String? description,
    required String priority,
    required String status,
    String? dueDate,
    required int completionPercentage,
    double? cost,
    String? clientId,
    bool clearClient = false,
    String? teamId,
    String? editedBy,
    String? editSummary,
  }) async {
    try {
      final payload = <String, dynamic>{
        'title': title,
        'priority': priority,
        'status': status,
        'due_date': dueDate,
        'completion_percentage': completionPercentage,
        // explicit null clears the FK; only set when admin chose to change it
        if (clientId != null || clearClient) 'client_id': clientId,
        'team_id': teamId,
      };
      if (description != null) payload['description'] = description;
      if (cost != null) payload['cost'] = cost;
      if (cost == null) payload['cost'] = null;

      await _client.from('tasks').update(payload).eq('id', id);

      // Log the edit (fire-and-forget — missing table is fine)
      if (editedBy != null) {
        await logTaskEdit(id, editedBy, editSummary ?? 'Task updated');
      }

      try {
        final taskData = await fetchTaskDetail(id);
        if (taskData != null) {
          final assignees = taskData['assignees'] as List? ?? [];
          final assigneeIds = assignees.map((a) => a['id'] as String).toList();
          await NotificationRepository.notifyAction(
            title: 'Task Updated',
            body: 'Task "$title" details were updated.',
            type: 'task_updated',
            referenceType: 'task',
            referenceId: id,
            teamId: teamId,
            targetUserIds: assigneeIds,
            actorId: editedBy,
          );
        }
      } catch (_) {}

      return true;
    } on PostgrestException catch (e) {
      throw Exception('Task update failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw Exception('Task update error: $e');
    }
  }

  /// Employee-only save: update ONLY status and completion_percentage.
  static Future<bool> updateTaskStatusAndProgress({
    required String id,
    required String status,
    required int completionPercentage,
    String? editedBy,
  }) async {
    try {
      await _client
          .from('tasks')
          .update({
            'status': status,
            'completion_percentage': completionPercentage,
          })
          .eq('id', id);

      if (editedBy != null) {
        await logTaskEdit(id, editedBy, 'Status / progress updated');
      }

      try {
        final taskData = await fetchTaskDetail(id);
        if (taskData != null) {
          final title = taskData['title'] as String? ?? 'Task';
          final teamId = taskData['team_id'] as String?;
          final assignees = taskData['assignees'] as List? ?? [];
          final assigneeIds = assignees.map((a) => a['id'] as String).toList();

          await NotificationRepository.notifyAction(
            title: 'Task Progress Updated',
            body: 'Task "$title" progress updated to $completionPercentage% ($status).',
            type: 'task_status_changed',
            referenceType: 'task',
            referenceId: id,
            teamId: teamId,
            targetUserIds: assigneeIds,
            actorId: editedBy,
          );
        }
      } catch (_) {}

      return true;
    } on PostgrestException catch (e) {
      throw Exception('Update failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw Exception('Update error: $e');
    }
  }

  static Future<bool> deleteTask(String id) async {
    try {
      String? title;
      String? teamId;
      List<String> assigneeIds = [];
      try {
        final taskData = await fetchTaskDetail(id);
        if (taskData != null) {
          title = taskData['title'] as String?;
          teamId = taskData['team_id'] as String?;
          final assignees = taskData['assignees'] as List? ?? [];
          assigneeIds = assignees.map((a) => a['id'] as String).toList();
        }
      } catch (_) {}

      await _client.from('tasks').delete().eq('id', id);

      if (title != null) {
        try {
          await NotificationRepository.notifyAction(
            title: 'Task Deleted',
            body: 'Task "$title" was removed.',
            type: 'task_deleted',
            teamId: teamId,
            targetUserIds: assigneeIds,
          );
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateTaskAssignees(
    String taskId,
    List<String> profileIds, {
    required String assignedBy,
  }) {
    return assignEmployees(
      taskId: taskId,
      profileIds: profileIds,
      assignedBy: assignedBy,
    );
  }

  /// Replaces the task_assignees list for [taskId].
  static Future<bool> assignEmployees({
    required String taskId,
    required List<String> profileIds,
    required String assignedBy,
  }) async {
    try {
      await _client.from('task_assignees').delete().eq('task_id', taskId);

      if (profileIds.isNotEmpty) {
        final inserts = profileIds
            .map(
              (pId) => {
                'task_id': taskId,
                'profile_id': pId,
                'is_lead': pId == profileIds.first,
                'assigned_by': assignedBy,
              },
            )
            .toList();
        await _client.from('task_assignees').insert(inserts);
      }

      // Notify the employees, team lead (manager), and ALL admins & super admins
      try {
        final taskData = await fetchTaskDetail(taskId);
        if (taskData != null) {
          final title = taskData['title'] as String? ?? 'New Task';
          final teamId = taskData['team_id'] as String?;

          await NotificationRepository.notifyAction(
            title: 'Task Assigned',
            body: 'Task "$title" has been assigned to team members.',
            type: 'task_assigned',
            referenceType: 'task',
            referenceId: taskId,
            teamId: teamId,
            targetUserIds: profileIds,
            actorId: assignedBy,
          );
        }
      } catch (_) {}

      return true;
    } on PostgrestException catch (e) {
      throw Exception('Assignees update failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw Exception('Assignees update error: $e');
    }
  }
}
