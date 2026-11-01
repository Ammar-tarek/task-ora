// lib/features/tasks/task_month_visibility.dart
// Pure month-view visibility for the task board. The board is a month view:
// a task shows only when its monthAnchor equals the active month.
// Exception: a task still awaiting THIS viewer's Accept/Reject response is kept
// in every month, so a newly-assigned task is never lost behind the month
// filter (e.g. a Nov-due task assigned while viewing Oct). Once accepted it
// follows the normal month filter — so OLD accepted tasks never leak into the
// current month. All other tasks keep the normal month filter. Pure + tested.

import '../../core/models/task_model.dart';

class TaskMonthVisibility {
  TaskMonthVisibility._();

  /// Keep [t] for [activeMonth] when it is anchored there, OR when [viewerId]
  /// is an assignee of [t] whose response is still PENDING (so they can respond
  /// from any month). Accepted/rejected/legacy assignments follow the month
  /// filter — this prevents previous-month tasks appearing in the current month.
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
