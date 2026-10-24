// test/task_audit_insert_test.dart
// Regression for the task_audit_log 403: the client must stamp actor_id with the
// ACTING user (never a forged id), matching the RLS CHECK actor_id = auth.uid().

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/repositories/task_repository.dart';

void main() {
  group('TaskRepository.buildAuditInsert', () {
    test('stamps actor_id with the acting user (no forging)', () {
      final row = TaskRepository.buildAuditInsert(
        taskId: 'task-1',
        actorId: 'user-self',
        notes: 'Status / progress updated',
      );
      expect(row['actor_id'], 'user-self');
      expect(row['task_id'], 'task-1');
      expect(row['action'], 'edit');
      expect(row['notes'], 'Status / progress updated');
    });

    test('actor_id is always the passed actor, not a constant or other id', () {
      final a = TaskRepository.buildAuditInsert(
        taskId: 't',
        actorId: 'emp-A',
        notes: 'x',
      );
      final b = TaskRepository.buildAuditInsert(
        taskId: 't',
        actorId: 'emp-B',
        notes: 'x',
      );
      expect(a['actor_id'], 'emp-A');
      expect(b['actor_id'], 'emp-B');
    });
  });
}
