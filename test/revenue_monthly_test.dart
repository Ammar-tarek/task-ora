// test/revenue_monthly_test.dart
// Phase C — monthly revenue math: per-month charges, partial/full payments,
// outstanding balances, multiple payments, month separation, no overwrite.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/repositories/finance_repository.dart';
import 'package:task_ora/features/finance/monthly_revenue.dart';

CrmEntry _entry({
  required String id,
  required String clientId,
  required String clientName,
  required double amount,
  required double paid,
  String? entryDate,
  String status = 'unpaid',
}) =>
    CrmEntry(
      id: id,
      clientId: clientId,
      clientName: clientName,
      title: 'Entry $id',
      amount: amount,
      paidAmount: paid,
      status: status,
      sourceType: 'manual',
      entryDate: entryDate,
      currency: 'EGP',
    );

CrmPayment _pay({
  required String id,
  required double amount,
  required String date,
  String status = 'active',
}) =>
    CrmPayment(id: id, amountPaid: amount, paymentDate: date, status: status);

void main() {
  group('MonthlyRevenue.summarize', () {
    final entries = [
      // October 2026
      _entry(id: 'a1', clientId: 'A', clientName: 'Acme', amount: 10000, paid: 6000, entryDate: '2026-10-05'),
      _entry(id: 'b1', clientId: 'B', clientName: 'Globex', amount: 5000, paid: 5000, entryDate: '2026-10-10'),
      _entry(id: 'c1', clientId: 'C', clientName: 'Initech', amount: 8000, paid: 0, entryDate: '2026-10-20'),
      // Multiple entries for one client in the same month
      _entry(id: 'a2', clientId: 'A', clientName: 'Acme', amount: 2000, paid: 2000, entryDate: '2026-10-25'),
      // November 2026 (must not leak into October)
      _entry(id: 'a3', clientId: 'A', clientName: 'Acme', amount: 3000, paid: 0, entryDate: '2026-11-02'),
      // Cancelled → excluded
      _entry(id: 'x1', clientId: 'C', clientName: 'Initech', amount: 9999, paid: 0, entryDate: '2026-10-15', status: 'cancelled'),
    ];

    test('groups a client\'s month charges and computes total/paid/remaining', () {
      final rows = MonthlyRevenue.summarize(entries, 2026, 10);
      final acme = rows.firstWhere((r) => r.clientId == 'A');
      expect(acme.total, 12000); // 10000 + 2000
      expect(acme.paid, 8000); //  6000 + 2000
      expect(acme.remaining, 4000);
      expect(acme.entryCount, 2);
      expect(acme.status, PaymentStatus.partial);
    });

    test('full payment → Paid, zero remaining', () {
      final globex = MonthlyRevenue.summarize(entries, 2026, 10)
          .firstWhere((r) => r.clientId == 'B');
      expect(globex.remaining, 0);
      expect(globex.status, PaymentStatus.paid);
    });

    test('no payment → Unpaid, full remaining', () {
      final initech = MonthlyRevenue.summarize(entries, 2026, 10)
          .firstWhere((r) => r.clientId == 'C');
      expect(initech.total, 8000);
      expect(initech.paid, 0);
      expect(initech.remaining, 8000);
      expect(initech.status, PaymentStatus.unpaid);
    });

    test('cancelled entries are excluded', () {
      final initech = MonthlyRevenue.summarize(entries, 2026, 10)
          .firstWhere((r) => r.clientId == 'C');
      expect(initech.total, 8000); // the 9999 cancelled row is ignored
    });

    test('month separation: November is independent of October', () {
      final oct = MonthlyRevenue.summarize(entries, 2026, 10);
      final nov = MonthlyRevenue.summarize(entries, 2026, 11);
      // October Acme = 12000; November Acme = 3000 — neither overwrites the other.
      expect(oct.firstWhere((r) => r.clientId == 'A').total, 12000);
      expect(nov.firstWhere((r) => r.clientId == 'A').total, 3000);
      expect(nov.length, 1); // only Acme has a November charge
    });

    test('historical retrieval: re-running an old month yields the same figures', () {
      final first = MonthlyRevenue.summarize(entries, 2026, 10);
      final again = MonthlyRevenue.summarize(entries, 2026, 10);
      expect(first.map((r) => '${r.clientId}:${r.total}:${r.paid}'),
          again.map((r) => '${r.clientId}:${r.total}:${r.paid}'));
    });

    test('rows sort by remaining desc (biggest debt first)', () {
      final rows = MonthlyRevenue.summarize(entries, 2026, 10);
      final remaining = rows.map((r) => r.remaining).toList();
      final sorted = [...remaining]..sort((a, b) => b.compareTo(a));
      expect(remaining, sorted);
      expect(rows.first.clientId, 'C'); // Initech 8000 outstanding
    });

    test('empty when no entries in the month', () {
      expect(MonthlyRevenue.summarize(entries, 2026, 12), isEmpty);
    });
  });

  group('MonthlyRevenue payments', () {
    final payments = [
      _pay(id: 'p1', amount: 3000, date: '2026-10-05'),
      _pay(id: 'p2', amount: 2000, date: '2026-10-15'),
      _pay(id: 'p3', amount: 1000, date: '2026-11-02'),
      _pay(id: 'p4', amount: 9999, date: '2026-10-20', status: 'voided'), // excluded
    ];

    test('paymentsInMonth excludes voided and other months, newest first', () {
      final oct = MonthlyRevenue.paymentsInMonth(payments, 2026, 10);
      expect(oct.map((p) => p.id), ['p2', 'p1']); // 15th before 5th
    });

    test('multiple payments per month sum correctly', () {
      expect(MonthlyRevenue.paymentsTotal(payments, 2026, 10), 5000);
      expect(MonthlyRevenue.paymentsTotal(payments, 2026, 11), 1000);
    });

    test('voided payment never counts', () {
      expect(MonthlyRevenue.paymentsInMonth(payments, 2026, 10).any((p) => p.isVoided),
          isFalse);
    });
  });

  group('MonthlyRevenue.totals', () {
    test('company totals sum the rows', () {
      final entries = [
        _entry(id: '1', clientId: 'A', clientName: 'Acme', amount: 10000, paid: 6000, entryDate: '2026-10-01'),
        _entry(id: '2', clientId: 'B', clientName: 'Globex', amount: 5000, paid: 5000, entryDate: '2026-10-02'),
      ];
      final t = MonthlyRevenue.totals(MonthlyRevenue.summarize(entries, 2026, 10));
      expect(t.total, 15000);
      expect(t.paid, 11000);
      expect(t.remaining, 4000);
    });
  });
}
