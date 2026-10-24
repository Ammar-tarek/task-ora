// test/montage_completion_test.dart
// Manager confirmation: only a Montage manager/admin can flip an employee-done
// task to 'completed'. Employees never can (completion stays confirmation-gated),
// and confirmation maps to the real enum value 'completed'.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/features/tasks/montage_completion.dart';

void main() {
  group('MontageCompletion', () {
    test('confirmation maps to the enum value completed', () {
      expect(MontageCompletion.confirmedStatus, 'completed');
      expect(MontageCompletion.pendingStatus, 'employee_done');
    });

    test('Montage manager/admin may confirm an employee_done task', () {
      expect(
        MontageCompletion.managerCanConfirm(
          isMontage: true,
          canEditFull: true,
          status: 'employee_done',
        ),
        isTrue,
      );
    });

    test('employee (no full edit) can NEVER confirm — completion stays gated', () {
      expect(
        MontageCompletion.managerCanConfirm(
          isMontage: true,
          canEditFull: false,
          status: 'employee_done',
        ),
        isFalse,
      );
    });

    test('non-Montage tasks are unaffected', () {
      expect(
        MontageCompletion.managerCanConfirm(
          isMontage: false,
          canEditFull: true,
          status: 'employee_done',
        ),
        isFalse,
      );
    });

    test('only an employee_done task can be confirmed (not in_progress/completed)', () {
      for (final s in ['not_started', 'in_progress', 'completed', 'on_hold']) {
        expect(
          MontageCompletion.managerCanConfirm(
            isMontage: true,
            canEditFull: true,
            status: s,
          ),
          isFalse,
          reason: 'status $s must not be confirmable',
        );
      }
    });
  });
}
