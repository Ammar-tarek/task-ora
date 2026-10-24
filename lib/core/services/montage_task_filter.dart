// lib/core/services/montage_task_filter.dart
// Pure predicate for the Montage-only quick filters shown below the month bar.
// Montage only — other departments never set these filters.
//
// Mapping (reuses existing fields, never a combined status):
//   'paid'      → payment_status == 'paid'
//   'not_paid'  → payment_status == 'not_paid'
//   'done'      → task status == 'completed'   (real task status, not payment)
//   'cancelled' → task status == 'cancelled'   (real task status, not payment)
//   null        → no filter (All)

import '../models/task_model.dart';

class MontageTaskFilter {
  MontageTaskFilter._();

  /// The four selectable filters plus All, as (value, label) in display order.
  static const List<(String?, String)> options = [
    (null, 'All'),
    ('paid', 'Paid'),
    ('not_paid', 'Not Paid'),
    ('done', 'Done'),
    ('cancelled', 'Cancelled'),
  ];

  /// True when [task] passes the active [filter]. A null filter passes all.
  static bool matches(TaskModel task, String? filter) {
    switch (filter) {
      case null:
        return true;
      case 'paid':
        return task.paymentStatus == 'paid';
      case 'not_paid':
        return task.paymentStatus == 'not_paid';
      case 'done':
        return task.status == 'completed';
      case 'cancelled':
        return task.status == 'cancelled';
      default:
        return true;
    }
  }
}
