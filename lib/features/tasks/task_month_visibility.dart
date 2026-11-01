// lib/features/tasks/task_month_visibility.dart
// Pure month-view visibility for the task board. The board is a month view:
// normally a task shows only when its monthAnchor equals the active month.
// Exception: a task the viewer is ASSIGNED to is kept in every month, so an
// assignee never loses their own task behind the month filter (e.g. a Nov-due
// task assigned to them while they view Oct) — pending OR accepted. A task they
// REJECTED (they declined it) follows the normal month filter. All other tasks
// keep the normal month filter. Pure + unit-tested (no Supabase/Flutter).

import '../../core/models/task_model.dart';

class TaskMonthVisibility {
  TaskMonthVisibility._();

  /// Keep [t] for [activeMonth] when it is anchored there, OR when [viewerId]
  /// is an assignee of [t] (any response except rejected) — so an assignee
  /// always sees tasks assigned to them, regardless of the month in view.
  static bool isVisible(TaskModel t, DateTime activeMonth, String? viewerId) {
    if (t.monthAnchor == activeMonth) return true;
    if (viewerId == null) return false;
    final a = t.assigneeFor(viewerId);
    return a != null && a.response != 'rejected';
  }

  /// Apply [isVisible] across [tasks]. Preserves order; never duplicates a task
  /// that is both in the active month and pending for the viewer.
  static List<TaskModel> filter(
    List<TaskModel> tasks,
    DateTime activeMonth,
    String? viewerId,
  ) => tasks.where((t) => isVisible(t, activeMonth, viewerId)).toList();
}
