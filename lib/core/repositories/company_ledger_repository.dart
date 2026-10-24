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

/// One ledger row with its running balance filled in.
class LedgerEntry {
  final String id;
  final String type; // 'deposit' | 'expense'
  final double amount;
  final String date; // yyyy-MM-dd
  final String description;
  final String createdAt;

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
        balanceAfter: b,
      );

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
        id: m['id'] as String? ?? '',
        type: m['txn_type'] as String? ?? 'expense',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        date: m['txn_date'] as String? ?? '',
        description: m['description'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
      );
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

  /// All ledger rows with running balances, oldest → newest. The UI reverses
  /// for display (newest first) but balances stay correct because they are
  /// computed chronologically here.
  static Future<List<LedgerEntry>> fetchAll() async {
    try {
      final data = await _client
          .from('company_ledger')
          .select()
          .order('txn_date', ascending: true)
          .order('created_at', ascending: true);
      final rows = (data as List)
          .map((m) => LedgerEntry.fromMap(m as Map<String, dynamic>))
          .toList();
      return withRunningBalance(rows);
    } catch (_) {
      return [];
    }
  }

  // ── Writes (atomic, admin-only, idempotent via client token) ──────────────

  /// Record a deposit. Returns null on success, else an error message.
  static Future<String?> addFunds({
    required double amount,
    required String date,
    String? description,
    required String clientToken,
  }) async {
    try {
      await _client.rpc('company_add_funds', params: {
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
}
