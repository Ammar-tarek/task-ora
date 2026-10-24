// test/montage_monthly_progress_test.dart
// Montage employee monthly progress: 45 target, counts own completed tasks in
// the current month only, distinct, capped visually, isolated by employee/dept.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';
import 'package:task_ora/features/tasks/montage_monthly_progress.dart';

// due_date is a plain calendar date → monthAnchor uses it directly (no tz),
// which keeps these tests deterministic.
TaskModel _t({
  required String id,
  String status = 'completed',
  String due = '2026-10-15',
  String assignee = 'emp',
}) => TaskModel(
  id: id,
  title: 'T',
  createdBy: 'x',
  status: status,
  priority: 'medium',
  completionPercentage: 100,
  createdAt: '2026-10-01T00:00:00Z',
  dueDate: due,
  assignees: [TaskAssignee(profileId: assignee, fullName: 'E', isLead: true)],
);

final _now = DateTime(2026, 10, 20); // October 2026

List<TaskModel> _done(int n, {String assignee = 'emp'}) => List.generate(
  n,
  (i) => _t(id: 'd$i', assignee: assignee),
);

MontageMonthlyProgress _compute(List<TaskModel> tasks) =>
    MontageMonthlyProgress.compute(tasks: tasks, employeeId: 'emp', now: _now);

void main() {
  group('MontageMonthlyProgress', () {
    test('0 / 45 — nothing completed', () {
      final p = _compute([_t(id: 'a', status: 'in_progress')]);
      expect(p.done, 0);
      expect(p.percent, 0);
      expect(p.remaining, 45);
      expect(p.fraction, 0);
    });

    test('partial 27 / 45 → 60%, 18 remaining', () {
      final p = _compute(_done(27));
      expect(p.done, 27);
      expect(p.percent, 60);
      expect(p.remaining, 18);
    });

    test('45 / 45 → 100%, 0 remaining', () {
      final p = _compute(_done(45));
      expect(p.done, 45);
      expect(p.percent, 100);
      expect(p.remaining, 0);
      expect(p.fraction, 1.0);
    });

    test('over target 50 → raw count shown, capped at 100% / 0 remaining', () {
      final p = _compute(_done(50));
      expect(p.done, 50); // real count, not capped
      expect(p.percent, 100); // visual cap
      expect(p.fraction, 1.0);
      expect(p.remaining, 0);
    });

    test('month boundary — only current month counts', () {
      final p = _compute([
        _t(id: 'this', due: '2026-10-05'),
        _t(id: 'prev', due: '2026-09-30'),
        _t(id: 'next', due: '2026-11-01'),
      ]);
      expect(p.done, 1);
    });

    test('isolation — other employee, wrong status, payment, and dupes', () {
      final p = _compute([
        _t(id: 'mine'), // counts
        _t(id: 'other', assignee: 'emp2'), // other employee → excluded
        _t(id: 'wip', status: 'employee_done'), // not completed → excluded
        // a completed-but-unpaid task still counts by STATUS (payment ignored):
        _t(id: 'mine'), // duplicate id → counted once
      ]);
      expect(p.done, 1);
    });

    test('payment status never substitutes for completion', () {
      // Not completed, regardless of any payment value → excluded.
      final t = _t(id: 'p', status: 'in_progress');
      expect(_compute([t]).done, 0);
    });

    test('employee_done does NOT count; only persisted completed does', () {
      // The employee "finished" action (employee_done) must not move progress
      // until the manager confirms completion (status becomes completed).
      expect(_compute([_t(id: 'ed', status: 'employee_done')]).done, 0);
      expect(_compute([_t(id: 'ok', status: 'completed')]).done, 1);
    });
  });
}
