// lib/features/tasks/task_month_visibility.dart
// Pure month-view visibility for the task board. The board is a month view:
// normally a task shows only when its monthAnchor equals the active month.
// Exception: a task awaiting THIS viewer's Accept/Reject response is kept in
// every month, so an assignee can always find and respond to it. All other
// tasks keep the normal month filter. Pure + unit-tested (no Supabase/Flutter).

import '../../core/models/task_model.dart';

class TaskMonthVisibility {
  TaskMonthVisibility._();

  /// Keep [t] for [activeMonth] when it is anchored there, OR when [viewerId]
  /// is an assignee of [t] whose assignment response is still pending.
  static bool isVisible(TaskModel t, DateTime activeMonth, String? viewerId) {
    if (t.monthAnchor == activeMonth) return true;
    return t.isPendingAssignmentFor(viewerId);
  }

  /// Apply [isVisible] across [tasks]. Preserves order; never duplicates a task
  /// that is both in the active month and pending for the viewer.
  static List<TaskModel> filter(
    List<TaskModel> tasks,
    DateTime activeMonth,
    String? viewerId,
  ) => tasks.where((t) => isVisible(t, activeMonth, viewerId)).toList();
}
