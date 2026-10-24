// Pure task-summary bucket logic for the Team performance hub.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';
import 'package:task_ora/features/team/team_performance_repository.dart';

const _emp = 'emp-1';

TaskModel _task(String status, {String? response, String? reason}) => TaskModel(
      id: '$status-${response ?? "legacy"}',
      title: 'T',
      createdBy: 'mgr',
      status: status,
      priority: 'medium',
      completionPercentage: 0,
      createdAt: '2026-10-01T00:00:00Z',
      assignees: [
        TaskAssignee(
          profileId: _emp,
          fullName: 'Emp',
          isLead: true,
          response: response,
          responseReason: reason,
        ),
      ],
    );

void main() {
  group('EmployeeTaskSummary (single bucket, no double count)', () {
    test('buckets map to the right counts', () {
      final tasks = [
        _task('not_started', response: 'pending'),       // awaiting acceptance
        _task('in_progress', response: 'accepted'),       // in progress
        _task('employee_done', response: 'accepted'),     // awaiting review
        _task('completed', response: 'accepted'),         // completed
        _task('client_approved', response: null),         // completed (legacy)
        _task('changes_requested', response: 'accepted'), // changes requested
        _task('not_started', response: 'rejected', reason: 'busy'), // assignment rejected
      ];
      final rows = TeamPerformanceRepository.rowsFor(tasks, _emp);
      final s = TeamPerformanceRepository.summarize(rows);

      expect(s.assigned, 7);
      expect(s.awaitingAcceptance, 1);
      expect(s.inProgress, 1);
      expect(s.awaitingReview, 1);
      expect(s.completed, 2);
      expect(s.changesRequested, 1);
      expect(s.assignmentRejected, 1);
    });

    test('pending acceptance wins over status (not counted as in_progress)', () {
      final rows = TeamPerformanceRepository.rowsFor(
        [_task('in_progress', response: 'pending')],
        _emp,
      );
      final s = TeamPerformanceRepository.summarize(rows);
      expect(s.awaitingAcceptance, 1);
      expect(s.inProgress, 0);
    });

    test('assignment rejection is distinct from management changes-requested', () {
      final rows = TeamPerformanceRepository.rowsFor(
        [_task('not_started', response: 'rejected', reason: 'no')],
        _emp,
      );
      final s = TeamPerformanceRepository.summarize(rows);
      expect(s.assignmentRejected, 1);
      expect(s.changesRequested, 0);
    });
  });
}
