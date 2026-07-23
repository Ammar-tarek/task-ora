// lib/core/models/task_model.dart
// Matches public.tasks table + joined assignees, comments, edit logs.

import '../utils/app_time.dart';

class TaskModel {
  final String id;
  final String title;
  final String? description;
  final String? clientId;
  final String? clientName;
  final String? teamId;
  final String? handoffToTeamId; // pending handoff → target dept manager
  final String? handoffFromTeamId; // source dept
  final String? parentTaskId;
  final String createdBy;
  final String
  status; // 'not_started' | 'in_progress' | 'employee_done' | 'client_approved' | 'client_rejected' | 'completed' | 'on_hold'
  final String priority; // 'low' | 'medium' | 'high' | 'critical'
  final String? dueDate;
  final double? cost;
  final int completionPercentage;
  final String? boardId;
  final String? boardColumnId;
  final String createdAt;
  final List<TaskAssignee> assignees;
  final List<TaskComment> comments;
  final List<TaskEditLog> editLogs;

  const TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.clientId,
    this.clientName,
    this.teamId,
    this.handoffToTeamId,
    this.handoffFromTeamId,
    this.parentTaskId,
    required this.createdBy,
    required this.status,
    required this.priority,
    this.dueDate,
    this.cost,
    required this.completionPercentage,
    this.boardId,
    this.boardColumnId,
    required this.createdAt,
    this.assignees = const [],
    this.comments = const [],
    this.editLogs = const [],
  });

  factory TaskModel.fromMap(Map<String, dynamic> m) {
    final rawAssignees = m['task_assignees'] as List<dynamic>? ?? [];
    final rawComments = m['task_comments'] as List<dynamic>? ?? [];
    final rawEditLogs = m['task_edit_logs'] as List<dynamic>? ?? [];
    return TaskModel(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      description: m['description'] as String?,
      clientId: m['client_id'] as String?,
      clientName:
          (m['client'] as Map<String, dynamic>?)?['company_name'] as String?,
      teamId: m['team_id'] as String?,
      handoffToTeamId: m['handoff_to_team_id'] as String?,
      handoffFromTeamId: m['handoff_from_team_id'] as String?,
      parentTaskId: m['parent_task_id'] as String?,
      createdBy: m['created_by'] as String? ?? '',
      status: m['status'] as String? ?? 'not_started',
      priority: m['priority'] as String? ?? 'medium',
      dueDate: m['due_date'] as String?,
      cost: (m['cost'] as num?)?.toDouble(),
      completionPercentage: m['completion_percentage'] as int? ?? 0,
      boardId: m['board_id'] as String?,
      boardColumnId: m['board_column_id'] as String?,
      createdAt: m['created_at'] as String? ?? '',
      assignees: rawAssignees
          .map((a) => TaskAssignee.fromMap(a as Map<String, dynamic>))
          .toList(),
      comments: rawComments
          .map((c) => TaskComment.fromMap(c as Map<String, dynamic>))
          .toList(),
      editLogs: rawEditLogs
          .map((e) => TaskEditLog.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'not_started':
        return 'To Do';
      case 'in_progress':
        return 'In Progress';
      case 'employee_done':
        return 'Employee Done';
      case 'client_approved':
        return 'Client Approved';
      case 'client_rejected':
        return 'Client Rejected';
      case 'completed':
        return 'Completed';
      case 'on_hold':
        return 'On Hold';
      default:
        return status;
    }
  }

  String get priorityLabel {
    switch (priority) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      case 'critical':
        return 'Critical';
      default:
        return priority;
    }
  }

  String get dueDateDisplay {
    if (dueDate == null) return '—';
    try {
      final dt = AppTime.cairo(DateTime.parse(dueDate!));
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return dueDate!;
    }
  }

  String get leadAssigneeName =>
      assignees.isEmpty ? '—' : assignees.first.fullName;

  TaskModel copyWith({
    String? status,
    int? completionPercentage,
    List<TaskComment>? comments,
    List<TaskEditLog>? editLogs,
  }) {
    return TaskModel(
      id: id,
      title: title,
      description: description,
      clientId: clientId,
      clientName: clientName,
      teamId: teamId,
      handoffToTeamId: handoffToTeamId,
      handoffFromTeamId: handoffFromTeamId,
      parentTaskId: parentTaskId,
      createdBy: createdBy,
      status: status ?? this.status,
      priority: priority,
      dueDate: dueDate,
      cost: cost,
      completionPercentage: completionPercentage ?? this.completionPercentage,
      boardId: boardId,
      boardColumnId: boardColumnId,
      createdAt: createdAt,
      assignees: assignees,
      comments: comments ?? this.comments,
      editLogs: editLogs ?? this.editLogs,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class TaskAssignee {
  final String profileId;
  final String fullName;
  final bool isLead;

  const TaskAssignee({
    required this.profileId,
    required this.fullName,
    required this.isLead,
  });

  factory TaskAssignee.fromMap(Map<String, dynamic> m) {
    final profile = m['profile'] as Map<String, dynamic>?;
    return TaskAssignee(
      profileId: m['profile_id'] as String? ?? '',
      fullName: profile?['full_name'] as String? ?? 'Unknown',
      isLead: m['is_lead'] as bool? ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class TaskComment {
  final String id;
  final String content;
  final bool isInternal;
  final String createdAt;
  final String authorName;

  const TaskComment({
    required this.id,
    required this.content,
    required this.isInternal,
    required this.createdAt,
    required this.authorName,
  });

  factory TaskComment.fromMap(Map<String, dynamic> m) {
    final author = m['author'] as Map<String, dynamic>?;
    return TaskComment(
      id: m['id'] as String? ?? '',
      content: m['content'] as String? ?? '',
      isInternal: m['is_internal'] as bool? ?? true,
      createdAt: m['created_at'] as String? ?? '',
      authorName: author?['full_name'] as String? ?? 'Unknown',
    );
  }

  String get timeDisplay {
    try {
      final dt = AppTime.cairo(DateTime.parse(createdAt));
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, '
          '${AppTime.hm(dt)}';
    } catch (_) {
      return createdAt;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class TaskEditLog {
  final String id;
  final String editorName;
  final String editedAt;
  final String? summary;

  const TaskEditLog({
    required this.id,
    required this.editorName,
    required this.editedAt,
    this.summary,
  });

  factory TaskEditLog.fromMap(Map<String, dynamic> m) {
    // Supports both legacy task_edit_logs and current task_audit_log schemas.
    final editor = (m['editor'] ?? m['actor']) as Map<String, dynamic>?;
    return TaskEditLog(
      id: m['id'] as String? ?? '',
      editorName:
          editor?['full_name'] as String? ??
          m['editor_name'] as String? ??
          'Unknown',
      editedAt: m['edited_at'] as String? ?? m['created_at'] as String? ?? '',
      summary:
          m['summary'] as String? ??
          m['notes'] as String? ??
          m['action'] as String?,
    );
  }

  String get timeDisplay {
    try {
      final dt = AppTime.cairo(DateTime.parse(editedAt));
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, '
          '${AppTime.hm(dt)}';
    } catch (_) {
      return editedAt;
    }
  }
}
