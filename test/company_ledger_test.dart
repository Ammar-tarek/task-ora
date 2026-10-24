// Tests for the pure company-ledger calculations (no DB).
// Overspend rejection, admin authorization, and duplicate/concurrent handling
// are enforced server-side in PROPOSED_company_ledger.sql and validated there.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/repositories/company_ledger_repository.dart';

LedgerEntry _e(String type, double amt, String date) => LedgerEntry(
      id: '$type-$amt-$date',
      type: type,
      amount: amt,
      date: date,
      description: '',
      createdAt: '${date}T00:00:00Z',
    );

void main() {
  group('CompanyLedger running balance', () {
    test('deposits add, expenses subtract, in chronological order', () {
      final chrono = [
        _e('deposit', 1000, '2026-01-05'),
        _e('expense', 300, '2026-01-10'),
        _e('deposit', 200, '2026-02-01'),
        _e('expense', 150, '2026-02-15'),
      ];
      final withBal = CompanyLedgerRepository.withRunningBalance(chrono);
      expect(withBal[0].balanceAfter, 1000);
      expect(withBal[1].balanceAfter, 700);
      expect(withBal[2].balanceAfter, 900);
      expect(withBal[3].balanceAfter, 750);
    });

    test('balanceOf is all-time deposits minus expenses', () {
      final all = [
        _e('deposit', 1000, '2026-01-05'),
        _e('expense', 300, '2026-01-10'),
        _e('deposit', 200, '2026-02-01'),
      ];
      expect(CompanyLedgerRepository.balanceOf(all), 900);
    });
  });

  group('CompanyLedger monthly slicing', () {
    final all = [
      _e('deposit', 1000, '2026-01-05'),
      _e('expense', 300, '2026-01-10'),
      _e('expense', 50, '2026-01-20'),
      _e('deposit', 200, '2026-02-01'),
      _e('expense', 150, '2026-02-15'),
    ];

    test('inMonth returns only that month', () {
      expect(CompanyLedgerRepository.inMonth(all, 2026, 1).length, 3);
      expect(CompanyLedgerRepository.inMonth(all, 2026, 2).length, 2);
    });

    test('monthly expense total counts expenses only', () {
      expect(CompanyLedgerRepository.monthlyExpenseTotal(all, 2026, 1), 350);
      expect(CompanyLedgerRepository.monthlyExpenseTotal(all, 2026, 2), 150);
    });

    test('monthly expense count counts expenses only (not deposits)', () {
      expect(CompanyLedgerRepository.monthlyExpenseCount(all, 2026, 1), 2);
      expect(CompanyLedgerRepository.monthlyExpenseCount(all, 2026, 2), 1);
    });

    test('empty month yields zero total and zero count', () {
      expect(CompanyLedgerRepository.monthlyExpenseTotal(all, 2026, 3), 0);
      expect(CompanyLedgerRepository.monthlyExpenseCount(all, 2026, 3), 0);
      expect(CompanyLedgerRepository.inMonth(all, 2026, 3), isEmpty);
    });

    test('balance is unchanged by which month is viewed (carries forward)', () {
      // Balance is a function of ALL entries, not the selected month.
      final bal = CompanyLedgerRepository.balanceOf(all);
      expect(bal, 700); // 1000 - 300 - 50 + 200 - 150
    });
  });

  group('CompanyLedger token', () {
    test('newToken is a well-formed v4 uuid and unique', () {
      final a = CompanyLedgerRepository.newToken();
      final b = CompanyLedgerRepository.newToken();
      expect(a, isNot(b));
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(a),
        isTrue,
      );
    });
  });
}
