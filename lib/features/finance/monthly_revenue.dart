// lib/features/finance/monthly_revenue.dart
// Pure, UI-free monthly revenue math. Flutter-free so it is unit-testable.
//
// Model (confirmed against the schema + the user's rule "separate monthly client
// charges from actual payment transactions"):
//   • CHARGES  = crm_entries, anchored to a month by entry_date (the editable
//     revenue date; falls back to due_date, then created_at). Each entry carries
//     its own amount + cumulative paid_amount, so remaining is per-charge.
//   • PAYMENTS = crm_payments, anchored to a month by payment_date; 'voided'
//     transactions are excluded.
//
// Every figure is derived from immutable, dated rows, so each month is computed
// independently — a later month never overwrites an earlier one.

import '../../core/repositories/finance_repository.dart' show CrmEntry, CrmPayment;

/// Rounding guard so float sums don't make a fully-paid charge read 'partial'.
const double _eps = 0.005;

enum PaymentStatus { paid, partial, unpaid, none }

extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.unpaid => 'Unpaid',
        PaymentStatus.none => '—',
      };
}

/// One client's charge summary for a single month.
class ClientRevenueRow {
  final String clientId;
  final String clientName;
  final double total; // Σ amount of the month's charges
  final double paid; // Σ paid_amount against those charges
  final int entryCount;

  const ClientRevenueRow({
    required this.clientId,
    required this.clientName,
    required this.total,
    required this.paid,
    required this.entryCount,
  });

  /// Outstanding for the month, never negative (an overpaid charge is clamped;
  /// the audited RPC layer already blocks overpayment, so this is defensive).
  double get remaining => (total - paid) < 0 ? 0 : (total - paid);

  PaymentStatus get status {
    if (total <= 0) return PaymentStatus.none;
    if (paid <= _eps) return PaymentStatus.unpaid;
    if (paid + _eps >= total) return PaymentStatus.paid;
    return PaymentStatus.partial;
  }
}

class MonthlyRevenue {
  MonthlyRevenue._();

  /// (year, month) of an entry's revenue date: entry_date → due_date → created_at.
  static List<int>? _entryYm(CrmEntry e) =>
      _ym(e.entryDate) ?? _ym(e.dueDate) ?? _ym(e.createdAt);

  /// Parse a leading `yyyy-MM...` (date or ISO timestamp) into [year, month].
  static List<int>? _ym(String? s) {
    if (s == null || s.length < 7) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    if (y == null || m == null || m < 1 || m > 12) return null;
    return [y, m];
  }

  static bool _inMonth(List<int>? ym, int year, int month) =>
      ym != null && ym[0] == year && ym[1] == month;

  /// Charges dated in [year]/[month], excluding cancelled, grouped by client.
  /// Rows are sorted by remaining (desc), then name, so the biggest debts lead.
  static List<ClientRevenueRow> summarize(
    List<CrmEntry> entries,
    int year,
    int month,
  ) {
    final byClient = <String, _Acc>{};
    for (final e in entries) {
      if (e.status == 'cancelled') continue;
      if (!_inMonth(_entryYm(e), year, month)) continue;
      final key = e.clientId ?? '__none__';
      final acc = byClient.putIfAbsent(
        key,
        () => _Acc(key, e.clientName),
      );
      acc.total += e.amount;
      acc.paid += e.paidAmount;
      acc.count += 1;
      if (acc.name.isEmpty && e.clientName.isNotEmpty) acc.name = e.clientName;
    }
    final rows = byClient.values
        .map((a) => ClientRevenueRow(
              clientId: a.clientId,
              clientName: a.name.isEmpty ? 'Unknown client' : a.name,
              total: a.total,
              paid: a.paid,
              entryCount: a.count,
            ))
        .toList();
    rows.sort((x, y) {
      final r = y.remaining.compareTo(x.remaining);
      return r != 0 ? r : x.clientName.toLowerCase().compareTo(y.clientName.toLowerCase());
    });
    return rows;
  }

  /// Active (non-voided) payments whose payment_date falls in [year]/[month],
  /// most recent first.
  static List<CrmPayment> paymentsInMonth(
    List<CrmPayment> payments,
    int year,
    int month,
  ) {
    final list = payments
        .where((p) => !p.isVoided && _inMonth(_ym(p.paymentDate), year, month))
        .toList();
    list.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return list;
  }

  /// Total of active payments in [year]/[month].
  static double paymentsTotal(List<CrmPayment> payments, int year, int month) =>
      paymentsInMonth(payments, year, month)
          .fold(0.0, (sum, p) => sum + p.amountPaid);

  /// Company-wide totals for the month (for a header strip).
  static MonthlyTotals totals(List<ClientRevenueRow> rows) {
    double total = 0, paid = 0;
    for (final r in rows) {
      total += r.total;
      paid += r.paid;
    }
    return MonthlyTotals(total: total, paid: paid);
  }
}

class MonthlyTotals {
  final double total;
  final double paid;
  const MonthlyTotals({required this.total, required this.paid});
  double get remaining => (total - paid) < 0 ? 0 : (total - paid);
}

class _Acc {
  _Acc(this.clientId, this.name);
  final String clientId;
  String name;
  double total = 0;
  double paid = 0;
  int count = 0;
}
