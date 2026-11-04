// lib/core/repositories/company_ledger_repository.dart
// Central COMPANY cash ledger (deposits + expenses). Admin-only. Fully
// isolated from Department Finance and the shared `expenses` table — this reads
// and writes ONLY public.company_ledger via SECURITY DEFINER RPCs that enforce
// admin authorization and an atomic balance guard server-side.
//
// DEPLOYMENT DEPENDENCY: apply PROPOSED_company_ledger.sql first. Until then the
// RPCs/table do not exist and calls return an error string (handled by the UI).

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// One ledger row with its running balance filled in. A row is either a company
/// EXPENSE (from company_ledger) or a DEPOSIT. Deposits represent collected
/// DEPARTMENT REVENUE — ONE row per payment received (crm_payments), so a client
/// paying in installments shows a separate transaction each time. Each carries
/// the owning [department] and the admin who [recordedBy] that payment.
class LedgerEntry {
  final String id;
  final String type; // 'deposit' | 'expense'
  final double amount;
  final String date; // yyyy-MM-dd
  final String description;
  final String createdAt;

  /// Deposit-only context (null for expenses): the owning department's name and
  /// the full name of the admin who recorded the revenue.
  final String? department;
  final String? recordedBy;

  /// Balance AFTER this transaction, in chronological order. Filled by
  /// [CompanyLedgerRepository.withRunningBalance].
  final double balanceAfter;

  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.description,
    required this.createdAt,
    this.department,
    this.recordedBy,
    this.balanceAfter = 0,
  });

  bool get isDeposit => type == 'deposit';

  LedgerEntry copyWithBalance(double b) => LedgerEntry(
        id: id,
        type: type,
        amount: amount,
        date: date,
        description: description,
        createdAt: createdAt,
        department: department,
        recordedBy: recordedBy,
        balanceAfter: b,
      );

  /// A company_ledger row (expense, or any legacy deposit).
  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
        id: m['id'] as String? ?? '',
        type: m['txn_type'] as String? ?? 'expense',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        date: m['txn_date'] as String? ?? '',
        description: m['description'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
      );

  /// A deposit synthesized from a single collected payment (crm_payments row)
  /// with its parent revenue embedded as `entry`. [recorderNames] maps a
  /// profile id → full name. When the parent revenue has more than one payment,
  /// [paymentIndex]/[paymentCount] label this installment (e.g. "· payment 2/2")
  /// so two same-day collections are never mistaken for one — each new payment
  /// reads as its own, clearly distinct transaction.
  factory LedgerEntry.fromPayment(
    Map<String, dynamic> m,
    Map<String, String> recorderNames, {
    int paymentIndex = 1,
    int paymentCount = 1,
  }) {
    final createdAt = m['created_at'] as String? ?? '';
    final payDate = m['payment_date'] as String?;
    final date = (payDate != null && payDate.length >= 10)
        ? payDate.substring(0, 10)
        : (createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt);
    final entry = m['entry'] as Map<String, dynamic>?;
    final title = (entry?['title'] as String?)?.trim() ?? '';
    final team = entry?['team'] as Map<String, dynamic>?;
    final recordedBy = m['recorded_by'] as String?;
    final base = title.isEmpty ? 'Department revenue' : title;
    // Only tag installments when the revenue was actually split into several
    // payments — a single full payment stays clean.
    final label =
        paymentCount > 1 ? '$base · payment $paymentIndex/$paymentCount' : base;
    return LedgerEntry(
      id: m['id'] as String? ?? '',
      type: 'deposit',
      amount: (m['amount_paid'] as num?)?.toDouble() ?? 0,
      date: date,
      description: label,
      createdAt: createdAt,
      department: team?['name'] as String?,
      recordedBy: recordedBy == null ? null : recorderNames[recordedBy],
    );
  }

  /// "HH:mm" (Egypt time) of when this transaction was recorded, from
  /// [createdAt]. Empty when unparseable. Lets the ledger show the time so two
  /// transactions on the same day are visibly distinct.
  String get timeLabel {
    try {
      final utc = DateTime.parse(createdAt).toUtc();
      // Egypt is UTC+2 (EET) / +3 (EEST); the ledger only needs HH:mm, and the
      // 1h DST edge is immaterial here — use +2 like the rest of finance.
      final c = utc.add(const Duration(hours: 2));
      return '${c.hour.toString().padLeft(2, '0')}:'
          '${c.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

class CompanyLedgerRepository {
  static final _client = SupabaseService.client;

  /// A fresh RFC-4122 v4 UUID string, used as an idempotency token so a
  /// retried submission (double-tap, network retry) cannot create a duplicate.
  /// Generated once per submit attempt and reused on retry. No package needed.
  static String newToken() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10
    String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}'
        '-${s.substring(16, 20)}-${s.substring(20)}';
  }

  // ── Pure calculation helpers (unit-tested, no DB) ─────────────────────────

  /// Given entries in CHRONOLOGICAL order (oldest first), returns copies with
  /// [LedgerEntry.balanceAfter] set: deposits add, expenses subtract.
  static List<LedgerEntry> withRunningBalance(List<LedgerEntry> chronological) {
    double bal = 0;
    final out = <LedgerEntry>[];
    for (final e in chronological) {
      bal += e.isDeposit ? e.amount : -e.amount;
      out.add(e.copyWithBalance(bal));
    }
    return out;
  }

  /// All-time balance (deposits − expenses), independent of any month.
  static double balanceOf(List<LedgerEntry> entries) =>
      entries.fold(0.0, (s, e) => s + (e.isDeposit ? e.amount : -e.amount));

  /// Entries whose txn_date falls in [year]-[month].
  static List<LedgerEntry> inMonth(List<LedgerEntry> entries, int year, int month) {
    final m = month.toString().padLeft(2, '0');
    final prefix = '$year-$m';
    return entries.where((e) => e.date.startsWith(prefix)).toList();
  }

  /// Total EXPENSE amount within the given month.
  static double monthlyExpenseTotal(List<LedgerEntry> entries, int year, int month) =>
      inMonth(entries, year, month)
          .where((e) => !e.isDeposit)
          .fold(0.0, (s, e) => s + e.amount);

  /// Number of EXPENSE transactions within the given month.
  static int monthlyExpenseCount(List<LedgerEntry> entries, int year, int month) =>
      inMonth(entries, year, month).where((e) => !e.isDeposit).length;

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// All ledger rows with running balances, oldest → newest. Combines company
  /// EXPENSES (company_ledger) with DEPOSITS — one per collected payment
  /// (crm_payments, active, whose manual parent revenue is not cancelled), so
  /// each installment a client pays is its own transaction. The UI reverses for
  /// display (newest first) but balances stay correct because they are computed
  /// chronologically here. This mirrors the server-side company_cash_balance():
  /// collected revenue − expenses.
  static Future<List<LedgerEntry>> fetchAll() async {
    try {
      final results = await Future.wait([
        // Company ledger: expenses (+ any legacy deposits).
        _client
            .from('company_ledger')
            .select()
            .order('txn_date', ascending: true)
            .order('created_at', ascending: true),
        // Collected department revenue → one deposit per active payment.
        // Inner-join the parent revenue so we can drop cancelled/non-manual.
        _client
            .from('crm_payments')
            .select('id, crm_entry_id, amount_paid, payment_date, created_at, '
                'recorded_by, entry:crm_entries!inner(title, status, '
                'source_type, team:teams(name))')
            .eq('status', 'active'),
      ]);

      final ledgerRows = (results[0] as List)
          .map((m) => LedgerEntry.fromMap(m as Map<String, dynamic>))
          .toList();

      // Keep only payments whose parent is a non-cancelled manual revenue.
      final paymentRaw = (results[1] as List)
          .cast<Map<String, dynamic>>()
          .where((m) {
        final e = m['entry'] as Map<String, dynamic>?;
        return e != null &&
            e['source_type'] == 'manual' &&
            e['status'] != 'cancelled';
      }).toList();
      // Resolve the recorder names (recorded_by → full_name) in one read.
      final recorderNames = await _fetchRecorderNames(
        paymentRaw
            .map((m) => m['recorded_by'] as String?)
            .whereType<String>()
            .toSet(),
      );
      // Number installments PER parent revenue: group by crm_entry_id, order
      // each group chronologically, then tag each payment i/n. This is what
      // turns two same-day 500s into "payment 1/2" and "payment 2/2".
      final byEntry = <String, List<Map<String, dynamic>>>{};
      for (final m in paymentRaw) {
        final eid = m['crm_entry_id'] as String? ?? m['id'] as String? ?? '';
        byEntry.putIfAbsent(eid, () => []).add(m);
      }
      final revenueRows = <LedgerEntry>[];
      for (final group in byEntry.values) {
        group.sort((a, b) => (a['created_at'] as String? ?? '')
            .compareTo(b['created_at'] as String? ?? ''));
        for (var i = 0; i < group.length; i++) {
          revenueRows.add(LedgerEntry.fromPayment(
            group[i],
            recorderNames,
            paymentIndex: i + 1,
            paymentCount: group.length,
          ));
        }
      }

      // Merge and order chronologically (date, then created_at) so running
      // balances are correct regardless of source. ISO strings sort lexically.
      final merged = [...ledgerRows, ...revenueRows]..sort((a, b) {
          final d = a.date.compareTo(b.date);
          return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
        });
      return withRunningBalance(merged);
    } catch (_) {
      return [];
    }
  }

  /// Map profile id → full name for the given recorder ids (admin-readable).
  static Future<Map<String, String>> _fetchRecorderNames(
      Set<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', ids.toList());
      return {
        for (final r in rows as List)
          (r['id'] as String): (r['full_name'] as String? ?? ''),
      };
    } catch (_) {
      return {};
    }
  }

  // ── Writes (atomic, admin-only, idempotent via client token) ──────────────

  /// Record a company expense. Server rejects invalid amounts and overspend.
  /// Returns null on success, else an error message.
  static Future<String?> recordExpense({
    required double amount,
    required String date,
    required String description,
    required String clientToken,
  }) async {
    try {
      await _client.rpc('company_record_expense', params: {
        'p_amount': amount,
        'p_date': date,
        'p_description': description,
        'p_client_token': clientToken,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Reset the AVAILABLE balance to zero by recording a single balancing expense
  /// equal to [currentBalance]. The ledger stays append-only, so the full
  /// history is kept (the reset shows as a "Balance reset" entry) and the
  /// server's admin + overspend guards still apply. Returns null on success,
  /// else a message. No DB migration needed — it reuses company_record_expense.
  static Future<String?> resetBalanceToZero({
    required double currentBalance,
    required String clientToken,
  }) async {
    if (currentBalance <= 0) {
      return 'Balance is already zero — nothing to reset.';
    }
    return recordExpense(
      amount: currentBalance,
      date: DateTime.now().toIso8601String().split('T').first,
      description: 'Balance reset',
      clientToken: clientToken,
    );
  }
}
