// test/task_month_anchor_test.dart
// Regression for the "created task invisible to everyone" bug: the task board
// is a MONTH view that filters by TaskModel.monthAnchor == activeMonth. A task
// whose due date is in another month anchors to the DUE month, so it is hidden
// while the board sits on the current (creation) month — for every role, since
// all roles share the same client-side month filter. The fix navigates the
// board to the new task's anchor month on create; these tests pin the anchor
// logic the fix relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';

TaskModel _task({String? dueDate, required String createdAt}) => TaskModel(
  id: 't',
  title: 'T',
  createdBy: 'u',
  status: 'not_started',
  priority: 'medium',
  completionPercentage: 0,
  createdAt: createdAt,
  dueDate: dueDate,
);

void main() {
  group('TaskModel.monthAnchor', () {
    test('due date in a later month anchors to the DUE month (the bug)', () {
      final t = _task(dueDate: '2026-11-03', createdAt: '2026-10-27T13:36:47Z');
      expect(t.monthAnchor, DateTime(2026, 11));
    });

    test('no due date anchors to the creation month', () {
      // Created 2026-10-27 (well inside October even after Cairo shift).
      final t = _task(createdAt: '2026-10-27T13:36:47Z');
      expect(t.monthAnchor, DateTime(2026, 10));
    });

    test('month view hides a future-due task but shows it in its due month', () {
      final octView = DateTime(2026, 10);
      final novView = DateTime(2026, 11);
      final t = _task(dueDate: '2026-11-03', createdAt: '2026-10-27T13:36:47Z');

      // Reproduces the report: created in October, invisible on the Oct board.
      expect(t.monthAnchor == octView, isFalse);
      // Visible once the board jumps to November (what the fix does on create).
      expect(t.monthAnchor == novView, isTrue);
    });

    test('same-month due date stays in the current month view', () {
      final t = _task(dueDate: '2026-10-30', createdAt: '2026-10-27T13:36:47Z');
      expect(t.monthAnchor, DateTime(2026, 10));
    });
  });
}
