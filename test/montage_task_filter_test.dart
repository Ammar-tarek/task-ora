// test/montage_task_filter_test.dart
// Montage-only quick filters: Paid/Not Paid read payment_status; Done/Cancelled
// read the real task status. Payment status is never treated as task status.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';
import 'package:task_ora/core/services/montage_task_filter.dart';

TaskModel _task({String status = 'in_progress', String? payment}) => TaskModel(
  id: 't',
  title: 'T',
  createdBy: 'u',
  status: status,
  paymentStatus: payment,
  priority: 'medium',
  completionPercentage: 0,
  createdAt: '2026-01-01',
);

void main() {
  group('MontageTaskFilter', () {
    test('null filter (All) passes every task', () {
      expect(MontageTaskFilter.matches(_task(), null), isTrue);
      expect(MontageTaskFilter.matches(_task(status: 'completed'), null), isTrue);
    });

    test('Paid / Not Paid filter the payment_status field', () {
      expect(MontageTaskFilter.matches(_task(payment: 'paid'), 'paid'), isTrue);
      expect(MontageTaskFilter.matches(_task(payment: 'not_paid'), 'paid'), isFalse);
      expect(MontageTaskFilter.matches(_task(payment: 'not_paid'), 'not_paid'), isTrue);
      expect(MontageTaskFilter.matches(_task(payment: null), 'paid'), isFalse);
    });

    test('Done / Cancelled filter the task status field, NOT payment', () {
      // A completed task that is still unpaid must match Done (status), and must
      // NOT match Paid (payment is distinct from completion).
      final doneUnpaid = _task(status: 'completed', payment: 'not_paid');
      expect(MontageTaskFilter.matches(doneUnpaid, 'done'), isTrue);
      expect(MontageTaskFilter.matches(doneUnpaid, 'paid'), isFalse);

      expect(MontageTaskFilter.matches(_task(status: 'cancelled'), 'cancelled'), isTrue);
      expect(MontageTaskFilter.matches(_task(status: 'completed'), 'cancelled'), isFalse);
      // 'done' must not be satisfied by a payment value of 'done' lookalikes.
      expect(MontageTaskFilter.matches(_task(status: 'in_progress', payment: 'done'), 'done'), isFalse);
    });
  });
}
