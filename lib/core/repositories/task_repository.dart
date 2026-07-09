// lib/core/repositories/task_repository.dart
// All Supabase queries related to tasks, boards, columns, assignees,
// comments, and edit history.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/profile_model.dart';
import '../services/supabase_service.dart';

class TaskRepository {
  static final _client      = SupabaseService.client;
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
    if (profile.isAdminOrManager) {
      final teamId = overrideTeamId ?? (profile.isManager ? profile.teamId : null);
      return _fetchAll(teamId: teamId);
    }
    if (profile.isEmployee) return _fetchEmployeeTasks(profile);
    if (profile.isClient)   return _fetchClientTasks(profile);
    return [];
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
    await _adminClient.from('tasks').update({
      'team_id':              null,
      'handoff_from_team_id': fromTeamId,
      'handoff_to_team_id':   toTeamId,
      'handoff_by':           byProfileId,
      'handoff_note':         note,
      'updated_at':           DateTime.now().toIso8601String(),
    }).eq('id', taskId);
    // Remove old assignees — new department will reassign.
    await _adminClient.from('task_assignees').delete().eq('task_id', taskId);
  }

  /// Target manager accepts a handoff into their department. The task becomes a
  /// normal team task visible to that team.
  static Future<void> acceptHandoff({
    required String taskId,
    required String teamId,
  }) async {
    await _adminClient.from('tasks').update({
      'team_id':            teamId,
      'handoff_to_team_id': null,
      'updated_at':         DateTime.now().toIso8601String(),
    }).eq('id', taskId);
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

  static Future<List<TaskModel>> _fetchClientTasks(
    ProfileModel profile,
  ) async {
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
        query = base.eq('created_by', userId).order('created_at', ascending: false);
      } else if (teamId != null) {
        query = base.eq('team_id', teamId).order('created_at', ascending: false);
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
          query = base.eq('created_by', userId).order('created_at', ascending: false);
        } else if (teamId != null) {
          query = base.eq('team_id', teamId).order('created_at', ascending: false);
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
      'not_started':     tasks.where((t) => t.status == 'not_started').toList(),
      'in_progress':     tasks.where((t) => t.status == 'in_progress').toList(),
      'employee_done':   tasks.where((t) => t.status == 'employee_done').toList(),
      'client_approved':  tasks.where((t) => t.status == 'client_approved').toList(),
      'client_rejected': tasks.where((t) => t.status == 'client_rejected').toList(),
      'completed':       tasks.where((t) => t.status == 'completed').toList(),
      'on_hold':         tasks.where((t) => t.status == 'on_hold').toList(),
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
          .select('*, task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name, avatar_url))')
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
        'task_id':  taskId,
        'actor_id': editedBy,
        'action':   'edit',
        'notes':    summary,
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
          .select('id, content, is_internal, created_at, author:profiles(full_name)')
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
        'task_id':     taskId,
        'author_id':   authorId,
        'content':     content,
        'is_internal': isInternal,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CRUD helpers
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await _client.from('tasks').update({'status': newStatus}).eq('id', taskId);
    } on PostgrestException catch (e) {
      throw Exception('Status update failed [${e.code}]: ${e.message}');
    }
  }

  static Future<void> updateTaskProgress(String taskId, int pct) async {
    await _client.from('tasks').update({
      'completion_percentage': pct,
    }).eq('id', taskId);
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
      final result = await _client.from('tasks').insert({
        'title':       title,
        'created_by':  createdBy,
        'team_id':     teamId,
        'client_id':   clientId,
        'description': description,
        'priority':    priority,
        'due_date':    dueDate,
        'status':      'not_started',
      }).select('id').single();
      return result['id'] as String;
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
    String? editedBy,
    String? editSummary,
  }) async {
    try {
      final payload = <String, dynamic>{
        'title':                title,
        'priority':             priority,
        'status':               status,
        'due_date':             dueDate,
        'completion_percentage': completionPercentage,
        // explicit null clears the FK; only set when admin chose to change it
        if (clientId != null || clearClient) 'client_id': clientId,
      };
      if (description != null) payload['description'] = description;
      if (cost != null) payload['cost'] = cost;
      if (cost == null) payload['cost'] = null;

      await _client.from('tasks').update(payload).eq('id', id);

      // Log the edit (fire-and-forget — missing table is fine)
      if (editedBy != null) {
        await logTaskEdit(id, editedBy, editSummary ?? 'Task updated');
      }

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
      await _client.from('tasks').update({
        'status':                status,
        'completion_percentage': completionPercentage,
      }).eq('id', id);

      if (editedBy != null) {
        await logTaskEdit(id, editedBy, 'Status / progress updated');
      }
      return true;
    } on PostgrestException catch (e) {
      throw Exception('Update failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw Exception('Update error: $e');
    }
  }

  static Future<bool> deleteTask(String id) async {
    try {
      await _client.from('tasks').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateTaskAssignees(
    String taskId,
    List<String> profileIds, {
    required String assignedBy,
  }) async {
    try {
      await _client.from('task_assignees').delete().eq('task_id', taskId);
      if (profileIds.isNotEmpty) {
        final inserts = profileIds.map((pId) => {
          'task_id':     taskId,
          'profile_id':  pId,
          'is_lead':     pId == profileIds.first,
          'assigned_by': assignedBy,
        }).toList();
        await _client.from('task_assignees').insert(inserts);
      }
      return true;
    } on PostgrestException catch (e) {
      throw Exception('Assignees update failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw Exception('Assignees update error: $e');
    }
  }
}
