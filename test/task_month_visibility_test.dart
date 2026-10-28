// test/task_month_visibility_test.dart
// Pending assignment-responses stay visible across months. The board month
// filter hides a task whose due month != active month, EXCEPT when the viewer
// is an assignee still awaiting Accept/Reject — those stay visible so they can
// respond. Everything else keeps the normal month filter.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';
import 'package:task_ora/features/tasks/task_month_visibility.dart';

const _me = 'me-1';
const _other = 'other-1';

TaskModel _task({
  required String id,
  String? dueDate,
  String createdAt = '2026-10-15T10:00:00Z',
  String assigneeId = _me,
  String? response, // null/accepted/rejected/pending
  bool hasAssignee = true,
}) => TaskModel(
  id: id,
  title: id,
  createdBy: 'mgr',
  status: 'not_started',
  priority: 'medium',
  completionPercentage: 0,
  createdAt: createdAt,
  dueDate: dueDate,
  assignees: hasAssignee
      ? [
          TaskAssignee(
            profileId: assigneeId,
            fullName: 'A',
            isLead: true,
            response: response,
          ),
        ]
      : const [],
);

void main() {
  final oct = DateTime(2026, 10);

  group('TaskMonthVisibility.isVisible', () {
    test('1. pending + future-month due → visible in October', () {
      final t = _task(id: 'nov', dueDate: '2026-11-03', response: 'pending');
      expect(TaskMonthVisibility.isVisible(t, oct, _me), isTrue);
    });

    test('2. pending + past-month due → still visible in October', () {
      final t = _task(id: 'sep', dueDate: '2026-09-03', response: 'pending');
      expect(TaskMonthVisibility.isVisible(t, oct, _me), isTrue);
    });

    test('3. pending but assigned to ANOTHER user → not visible out of month', () {
      final t = _task(
        id: 'nov-other',
        dueDate: '2026-11-03',
        assigneeId: _other,
        response: 'pending',
      );
      expect(TaskMonthVisibility.isVisible(t, oct, _me), isFalse);
    });

    test('4. accepted/rejected out of month → normal month filter (hidden)', () {
      final accepted =
          _task(id: 'nov-acc', dueDate: '2026-11-03', response: 'accepted');
      final rejected =
          _task(id: 'nov-rej', dueDate: '2026-11-03', response: 'rejected');
      final legacy = // null response = legacy, treated as accepted → not pending
          _task(id: 'nov-legacy', dueDate: '2026-11-03', response: null);
      expect(TaskMonthVisibility.isVisible(accepted, oct, _me), isFalse);
      expect(TaskMonthVisibility.isVisible(rejected, oct, _me), isFalse);
      expect(TaskMonthVisibility.isVisible(legacy, oct, _me), isFalse);
    });

    test('5. normal task (not pending) outside active month → hidden', () {
      final t = _task(
        id: 'nov-plain',
        dueDate: '2026-11-03',
        hasAssignee: false,
      );
      expect(TaskMonthVisibility.isVisible(t, oct, _me), isFalse);
    });

    test('null viewer never gets the exception', () {
      final t = _task(id: 'nov', dueDate: '2026-11-03', response: 'pending');
      expect(TaskMonthVisibility.isVisible(t, oct, null), isFalse);
    });
  });

  group('TaskMonthVisibility.filter', () {
    test('6. pending task INSIDE the active month appears exactly once', () {
      final t = _task(id: 'oct-pending', dueDate: '2026-10-20', response: 'pending');
      final out = TaskMonthVisibility.filter([t], oct, _me);
      expect(out.length, 1);
      expect(out.single.id, 'oct-pending');
    });

    test('mixed list: keeps in-month + my-pending, drops the rest', () {
      final tasks = [
        _task(id: 'oct-plain', dueDate: '2026-10-05', response: 'accepted'), // in month
        _task(id: 'nov-mine', dueDate: '2026-11-03', response: 'pending'),   // keep
        _task(id: 'nov-other', dueDate: '2026-11-03', assigneeId: _other, response: 'pending'), // drop
        _task(id: 'nov-plain', dueDate: '2026-11-09', hasAssignee: false),   // drop
      ];
      final ids = TaskMonthVisibility.filter(tasks, oct, _me).map((t) => t.id).toList();
      expect(ids, ['oct-plain', 'nov-mine']);
    });
  });

  group('7. task-creation anchor month (navigation target) unchanged', () {
    test('monthAnchor prefers due month; the create flow jumps there', () {
      final t = _task(id: 'nov', dueDate: '2026-11-03');
      expect(t.monthAnchor, DateTime(2026, 11));
    });
  });
}
