// lib/features/tasks/montage_monthly_progress.dart
// Pure monthly task-progress model for the Montage employee capacity bar.
//
// Rules (see requirements):
//  * Target = 45 tasks/month.
//  * Counts ONLY tasks whose actual task STATUS is 'completed' (the data model's
//    Done state) — never payment status, never other completion-like statuses.
//  * Counts ONLY tasks assigned to the given employee, in the current calendar
//    month (by due date, else creation date — the app's month-anchor rule).
//  * Distinct by task id (no double counting).
//  * Percentage is capped at 100% for display; the raw done count is shown as-is
//    even when it exceeds the target.
//  * Reads existing data only — never mutates or resets records.

import '../../core/models/task_model.dart';
import '../../core/utils/app_time.dart';

class MontageMonthlyProgress {
  final int done; // completed tasks assigned to the employee this month
  final int target;

  const MontageMonthlyProgress({required this.done, this.target = 45});

  /// Tasks still needed to reach the target (never negative).
  int get remaining => (target - done).clamp(0, target);

  /// Visual fraction 0.0–1.0, capped at 1.0 (the bar never overflows).
  double get fraction {
    if (target <= 0) return 0;
    final f = done / target;
    return f > 1 ? 1.0 : f;
  }

  /// Whole-percent for display, capped at 100.
  int get percent => (fraction * 100).round();

  /// Compute from the employee's loaded tasks. [now] defaults to the app's
  /// current time so the count resets naturally when the month changes.
  factory MontageMonthlyProgress.compute({
    required List<TaskModel> tasks,
    required String employeeId,
    DateTime? now,
    int target = 45,
  }) {
    final ref = now ?? AppTime.now();
    final month = DateTime(ref.year, ref.month);
    final counted = <String>{};
    for (final t in tasks) {
      if (t.status != 'completed') continue; // 'Done' = completed status only
      if (!t.assignees.any((a) => a.profileId == employeeId)) continue;
      final anchor = t.monthAnchor;
      if (anchor == null || anchor != month) continue;
      counted.add(t.id); // distinct ids → no double counting
    }
    return MontageMonthlyProgress(done: counted.length, target: target);
  }
}
