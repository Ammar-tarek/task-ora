// lib/core/repositories/analytics_repository.dart
// Real task analytics, scoped by team / department. Uses adminClient so a
// manager can read their whole team and an admin can read any department.

import '../services/supabase_service.dart';

class TaskStat {
  final String status;
  final String priority;
  final String? teamId;
  final int completion;
  final String? dueDate;
  final List<String> assignees;

  const TaskStat({
    required this.status,
    required this.priority,
    required this.teamId,
    required this.completion,
    required this.dueDate,
    required this.assignees,
  });

  factory TaskStat.fromMap(Map<String, dynamic> m) {
    final raw = m['task_assignees'] as List<dynamic>? ?? [];
    return TaskStat(
      status:     m['status'] as String? ?? 'not_started',
      priority:   m['priority'] as String? ?? 'medium',
      teamId:     m['team_id'] as String?,
      completion: m['completion_percentage'] as int? ?? 0,
      dueDate:    m['due_date'] as String?,
      assignees: raw
          .map((a) => (a['profile'] as Map<String, dynamic>?)?['full_name'] as String?)
          .whereType<String>()
          .toList(),
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    final d = DateTime.tryParse(dueDate!);
    return d != null && d.isBefore(DateTime.now());
  }
}

class AnalyticsRepository {
  static final _admin = SupabaseService.adminClient;

  /// Fetch task stats. Pass [teamIds] to scope (manager = own team, admin =
  /// a department's teams). Null = all teams.
  static Future<List<TaskStat>> fetchTaskStats({List<String>? teamIds}) async {
    try {
      if (teamIds != null && teamIds.isEmpty) return [];
      var q = _admin.from('tasks').select(
        'status, priority, team_id, completion_percentage, due_date, '
        'task_assignees(profile:profiles!task_assignees_profile_id_fkey(full_name))',
      );
      if (teamIds != null) q = q.inFilter('team_id', teamIds);
      final data = await q;
      return (data as List)
          .map((m) => TaskStat.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
