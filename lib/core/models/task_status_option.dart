// lib/core/models/task_status_option.dart
import 'package:flutter/material.dart';

class TaskStatusOption {
  final String id;
  final String columnId;
  final String label;   // enum key for built-ins; free text for custom
  final String color;   // hex e.g. '#2E7D32'
  final int position;
  final bool isDefault; // true = built-in, cannot be deleted

  const TaskStatusOption({
    required this.id,
    required this.columnId,
    required this.label,
    required this.color,
    this.position = 0,
    this.isDefault = false,
  });

  factory TaskStatusOption.fromMap(Map<String, dynamic> m) => TaskStatusOption(
        id:        m['id'] as String,
        columnId:  m['column_id'] as String,
        label:     m['label'] as String,
        color:     m['color'] as String? ?? '#888888',
        position:  m['position'] as int? ?? 0,
        isDefault: m['is_default'] as bool? ?? false,
      );

  /// Human-readable name shown in UI chips.
  String get displayLabel {
    switch (label) {
      case 'not_started':     return 'To Do';
      case 'in_progress':     return 'In Progress';
      case 'employee_done':   return 'Employee Done';
      case 'client_approve':  return 'Client Approved';
      case 'client_rejected': return 'Client Rejected';
      case 'completed':       return 'Completed';
      case 'on_hold':         return 'On Hold';
      default:                return label;
    }
  }

  Color get dartColor {
    try {
      return Color(int.parse('FF${color.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF888888);
    }
  }
}
