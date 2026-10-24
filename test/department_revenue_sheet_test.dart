// test/department_revenue_sheet_test.dart
// Locks the primary revenue table to exactly the required seven columns, in the
// required order. Guards against re-introducing Department / Status / Actions /
// duplicate payer columns.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/features/finance/department_revenue_sheet_screen.dart';

void main() {
  group('DepartmentRevenueSheetScreen.columnLabels', () {
    test('is exactly the seven required columns in order', () {
      expect(DepartmentRevenueSheetScreen.columnLabels, [
        'Date',
        'Entry / Description',
        'Client / Payer Name',
        'Total Price',
        'Amount Received',
        'Remaining Balance',
        'Notes',
      ]);
    });

    test('has no Department / Status / Actions columns', () {
      final cols = DepartmentRevenueSheetScreen.columnLabels;
      expect(cols.length, 7);
      expect(cols, isNot(contains('Department')));
      expect(cols, isNot(contains('Status')));
      expect(cols.where((c) => c.toLowerCase().contains('action')), isEmpty);
    });
  });
}
