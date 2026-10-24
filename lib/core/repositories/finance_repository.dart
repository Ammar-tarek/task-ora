// lib/core/repositories/finance_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../utils/currency.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrmEntry
// ─────────────────────────────────────────────────────────────────────────────

class CrmEntry {
  final String id;
  final String? clientId;
  final String clientName;
  final String? teamId;
  final String? teamName;
  final String title;
  final String? description; // legacy free-text; kept SEPARATE from notes
  final String? notes; // the dedicated crm_entries.notes column
  final double amount;
  final double paidAmount;
  final String status; // 'unpaid' | 'partial' | 'paid' | 'overdue' | 'cancelled'
  final String sourceType; // 'task' | 'room_booking' | 'meeting' | 'manual'
  final String? dueDate;
  final String? entryDate; // editable revenue date (M4), not created_at
  final String? payerName; // free-text payer (M4), not the CRM client's name
  final String? createdAt;
  final String? invoiceNumber;
  final String currency;

  const CrmEntry({
    required this.id,
    this.clientId,
    required this.clientName,
    this.teamId,
    this.teamName,
    required this.title,
    this.description,
    this.notes,
    required this.amount,
    required this.paidAmount,
    required this.status,
    required this.sourceType,
    this.dueDate,
    this.entryDate,
    this.payerName,
    this.createdAt,
    this.invoiceNumber,
    required this.currency,
  });

  factory CrmEntry.fromMap(Map<String, dynamic> m) {
    final client = m['client'] as Map<String, dynamic>?;
    final team = m['team'] as Map<String, dynamic>?;
    return CrmEntry(
      id: m['id'] as String,
      clientId: m['client_id'] as String?,
      clientName: client?['company_name'] as String? ?? 'Unknown Client',
      teamId: m['team_id'] as String?,
      teamName: team?['name'] as String?,
      title: m['title'] as String? ?? '',
      description: m['description'] as String?,
      notes: m['notes'] as String?,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (m['paid_amount'] as num?)?.toDouble() ?? 0,
      status: m['status'] as String? ?? 'unpaid',
      sourceType: m['source_type'] as String? ?? 'manual',
      dueDate: m['due_date'] as String?,
      entryDate: m['entry_date'] as String?,
      payerName: m['payer_name'] as String?,
      createdAt: m['created_at'] as String?,
      invoiceNumber: m['invoice_number'] as String?,
      currency: m['currency'] as String? ?? 'EGP',
    );
  }

  double get outstanding => amount - paidAmount;
  bool get isManual => sourceType == 'manual';

  /// Date shown in the sheet: the editable entry_date, falling back to the
  /// row's creation date for any legacy row the backfill somehow missed.
  String get displayDate {
    final d = entryDate ?? createdAt ?? '';
    return d.length >= 10 ? d.substring(0, 10) : (d.isEmpty ? '—' : d);
  }

  /// "Client / Payer Name" column value: the free-text payer when set,
  /// otherwise the linked client's company name (legacy fallback), else '—'.
  String get payerDisplay {
    final p = payerName?.trim() ?? '';
    if (p.isNotEmpty) return p;
    return clientId != null ? clientName : '—';
  }

  /// Notes column value for the UI (the dedicated `notes` column), never null.
  String get notesDisplay => notes ?? '';
  String get statusLabel {
    switch (status) {
      case 'unpaid':
        return 'Unpaid';
      case 'partial':
        return 'Partial';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CrmPayment — an individual payment transaction (for the audit/void UI)
// ─────────────────────────────────────────────────────────────────────────────

class CrmPayment {
  final String id;
  final double amountPaid;
  final String paymentDate;
  final String status; // 'active' | 'voided'
  final String? reference;
  final String? voidReason;

  const CrmPayment({
    required this.id,
    required this.amountPaid,
    required this.paymentDate,
    required this.status,
    this.reference,
    this.voidReason,
  });

  bool get isVoided => status == 'voided';

  factory CrmPayment.fromMap(Map<String, dynamic> m) => CrmPayment(
    id: m['id'] as String,
    amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
    paymentDate: m['payment_date'] as String? ?? '',
    status: m['status'] as String? ?? 'active',
    reference: m['reference_number'] as String?,
    voidReason: m['void_reason'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FinanceSummary — aggregated totals from all sources
// ─────────────────────────────────────────────────────────────────────────────

class FinanceSummary {
  final double taskRevenue;
  final double meetingRevenue;
  final double totalExpenses;
  final double totalInvoiced;
  final double totalPaid;
  final int pendingInvoices;
  final int overdueCount;

  const FinanceSummary({
    this.taskRevenue = 0,
    this.meetingRevenue = 0,
    this.totalExpenses = 0,
    this.totalInvoiced = 0,
    this.totalPaid = 0,
    this.pendingInvoices = 0,
    this.overdueCount = 0,
  });

  double get grossRevenue => taskRevenue + meetingRevenue + totalInvoiced;
  double get netProfit => grossRevenue - totalExpenses;
  double get outstanding => totalInvoiced - totalPaid;
}

// ─────────────────────────────────────────────────────────────────────────────
// FinanceRepository
// ─────────────────────────────────────────────────────────────────────────────

class FinanceRepository {
  // RLS-enforced client. B2: revenue/finance DATA reads (tasks, events,
  // expenses, crm) go through this so the database enforces scope —
  // admin: all; manager: own team's tasks/clients, zero expenses (admin-only);
  // client: own invoices. Reference lookups that only build narrowing id-lists
  // may stay on [_client].
  static final _client = SupabaseService.client;

  // ── CRM entries ───────────────────────────────────────────────────────────

  static Future<List<CrmEntry>> fetchCrmEntries({String? status}) async {
    try {
      final base = _client
          .from('crm_entries')
          .select('*, client:client_profiles(company_name)');
      final query = status != null
          ? base.eq('status', status).order('created_at', ascending: false)
          : base.order('created_at', ascending: false);
      final data = await query;
      return (data as List).map((m) => CrmEntry.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Aggregated summary (tasks + events + expenses + CRM) ──────────────────
  // Pass [teamId] to scope to one team (manager view).
  // Pass [clientType] to scope CRM invoices to a department's clients.

  static Future<FinanceSummary> fetchSummary({
    String? teamId,
    String? clientType,
  }) async {
    double taskRevenue = 0;
    double meetingRevenue = 0;
    double totalExpenses = 0;
    double totalInvoiced = 0;
    double totalPaid = 0;
    int pendingInvoices = 0;
    int overdueCount = 0;

    // If scoped to a department, resolve client IDs for CRM filtering
    List<String>? scopedClientIds;
    if (clientType != null) {
      try {
        final rows = await _client
            .from('client_profiles')
            .select('id')
            .or('client_type.eq.$clientType,client_type.eq.both');
        scopedClientIds = (rows as List).map((r) => r['id'] as String).toList();
      } catch (_) {
        scopedClientIds = [];
      }
    }

    // Only `tasks` and `profiles` carry team_id. Events/expenses are scoped
    // through the team's members (created_by / recorded_by).
    List<String>? memberIds;
    if (teamId != null) {
      try {
        final rows = await _client
            .from('profiles')
            .select('id')
            .eq('team_id', teamId);
        memberIds = (rows as List).map((r) => r['id'] as String).toList();
      } catch (_) {
        memberIds = [];
      }
    }

    await Future.wait([
      // Task costs (tasks have team_id)
      () async {
        try {
          var q = _client.from('tasks').select('cost').not('cost', 'is', null);
          if (teamId != null) q = q.eq('team_id', teamId);
          final rows = await q;
          taskRevenue = (rows as List).fold(
            0.0,
            (s, r) => s + ((r['cost'] as num?)?.toDouble() ?? 0),
          );
        } catch (_) {}
      }(),
      // Event / meeting costs (scoped by creator's team membership)
      () async {
        try {
          if (memberIds != null && memberIds.isEmpty) return;
          var q = _client.from('events').select('cost').not('cost', 'is', null);
          if (memberIds != null) q = q.inFilter('created_by', memberIds);
          final rows = await q;
          meetingRevenue = (rows as List).fold(
            0.0,
            (s, r) => s + ((r['cost'] as num?)?.toDouble() ?? 0),
          );
        } catch (_) {}
      }(),
      // Expenses (scoped by recorder's team membership)
      () async {
        try {
          if (memberIds != null && memberIds.isEmpty) return;
          // Expenses are admin-only under RLS → managers get zero (the agreed
          // "managers see no company-wide expenses" behavior).
          var q = _client.from('expenses').select('amount');
          if (memberIds != null) q = q.inFilter('recorded_by', memberIds);
          final rows = await q;
          totalExpenses = (rows as List).fold(
            0.0,
            (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0),
          );
        } catch (_) {}
      }(),
      // CRM invoices
      () async {
        try {
          var q = _client
              .from('crm_entries')
              .select('amount, paid_amount, status');
          if (scopedClientIds != null) {
            if (scopedClientIds.isEmpty) return; // no clients → no invoices
            q = q.inFilter('client_id', scopedClientIds);
          }
          final rows = await q;
          for (final r in rows as List) {
            totalInvoiced += (r['amount'] as num?)?.toDouble() ?? 0;
            totalPaid += (r['paid_amount'] as num?)?.toDouble() ?? 0;
            final st = r['status'] as String? ?? '';
            if (st != 'paid') pendingInvoices++;
            if (st == 'overdue') overdueCount++;
          }
        } catch (_) {}
      }(),
    ]);

    return FinanceSummary(
      taskRevenue: taskRevenue,
      meetingRevenue: meetingRevenue,
      totalExpenses: totalExpenses,
      totalInvoiced: totalInvoiced,
      totalPaid: totalPaid,
      pendingInvoices: pendingInvoices,
      overdueCount: overdueCount,
    );
  }

  // ── Monthly revenue breakdown (last 6 months, tasks + events) ────────────
  // Pass [teamId] to scope to one team (manager view).

  static Future<List<Map<String, dynamic>>> fetchMonthlyBreakdown({
    String? teamId,
  }) async {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();

    // Build ordered map for the last 6 months (oldest → newest)
    final orderedKeys = <String>[];
    final months = <String, double>{};
    for (int i = 5; i >= 0; i--) {
      final dt = DateTime(now.year, now.month - i);
      final key = '${monthNames[dt.month - 1]} ${dt.year}';
      orderedKeys.add(key);
      months[key] = 0;
    }

    String keyFor(String? isoDate) {
      if (isoDate == null) return '';
      final dt = DateTime.tryParse(isoDate);
      if (dt == null) return '';
      return '${monthNames[dt.month - 1]} ${dt.year}';
    }

    // Resolve team members for scoping events (events have no team_id).
    List<String>? memberIds;
    if (teamId != null) {
      try {
        final rows = await _client
            .from('profiles')
            .select('id')
            .eq('team_id', teamId);
        memberIds = (rows as List).map((r) => r['id'] as String).toList();
      } catch (_) {
        memberIds = [];
      }
    }

    await Future.wait([
      () async {
        try {
          var q = _client
              .from('tasks')
              .select('cost, created_at')
              .not('cost', 'is', null);
          if (teamId != null) q = q.eq('team_id', teamId);
          final rows = await q;
          for (final r in rows as List) {
            final k = keyFor(r['created_at'] as String?);
            if (months.containsKey(k)) {
              months[k] = months[k]! + ((r['cost'] as num?)?.toDouble() ?? 0);
            }
          }
        } catch (_) {}
      }(),
      () async {
        try {
          if (memberIds != null && memberIds.isEmpty) return;
          var q = _client
              .from('events')
              .select('cost, start_time')
              .not('cost', 'is', null);
          if (memberIds != null) q = q.inFilter('created_by', memberIds);
          final rows = await q;
          for (final r in rows as List) {
            final k = keyFor(r['start_time'] as String?);
            if (months.containsKey(k)) {
              months[k] = months[k]! + ((r['cost'] as num?)?.toDouble() ?? 0);
            }
          }
        } catch (_) {}
      }(),
    ]);

    // Return in chronological order with short month label for chart
    return orderedKeys.map((k) {
      final short = k.split(' ').first; // 'Jan', 'Feb' …
      return {'month': short, 'value': months[k] ?? 0.0, '_key': k};
    }).toList();
  }

  // ── Top clients by task revenue ───────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchTopClients({
    int limit = 5,
  }) async {
    try {
      final rows = await _client
          .from('tasks')
          .select('client_id, cost, client:client_profiles(company_name)')
          .not('client_id', 'is', null)
          .not('cost', 'is', null);

      final Map<String, Map<String, dynamic>> map = {};
      for (final r in rows as List) {
        final clientId = r['client_id'] as String;
        final name =
            (r['client'] as Map<String, dynamic>?)?['company_name']
                as String? ??
            'Unknown';
        final cost = (r['cost'] as num?)?.toDouble() ?? 0;
        map.putIfAbsent(
          clientId,
          () => {'name': name, 'revenue': 0.0, 'tasks': 0},
        );
        map[clientId]!['revenue'] =
            (map[clientId]!['revenue'] as double) + cost;
        map[clientId]!['tasks'] = (map[clientId]!['tasks'] as int) + 1;
      }

      return (map.values.toList()..sort(
            (a, b) =>
                (b['revenue'] as double).compareTo(a['revenue'] as double),
          ))
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Expense breakdown by category ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchExpensesByCategory() async {
    try {
      final rows = await _client
          .from('expenses')
          .select('amount, category:expense_categories(name)');

      final Map<String, double> cats = {};
      double total = 0;
      for (final r in rows as List) {
        final name =
            (r['category'] as Map<String, dynamic>?)?['name'] as String? ??
            'Other';
        final amount = (r['amount'] as num?)?.toDouble() ?? 0;
        cats[name] = (cats[name] ?? 0) + amount;
        total += amount;
      }

      if (total == 0) return [];

      return (cats.entries
          .map(
            (e) => {
              'label': e.key,
              'value': e.value / total * 100,
              'amount': e.value,
            },
          )
          .toList()
        ..sort(
          (a, b) => (b['value'] as double).compareTo(a['value'] as double),
        ));
    } catch (_) {
      return [];
    }
  }

  // ── Department revenue sheet (manual entries only; no project/task column) ──
  // Admin/super-admin only (RLS). Pass [teamId] to scope to one department.

  static Future<List<CrmEntry>> fetchManualRevenue({String? teamId}) async {
    try {
      var q = _client
          .from('crm_entries')
          .select(
            '*, client:client_profiles(company_name), team:teams(name)',
          )
          .eq('source_type', 'manual');
      if (teamId != null) q = q.eq('team_id', teamId);
      final data = await q
          .order('entry_date', ascending: false)
          .order('created_at', ascending: false);
      return (data as List).map((m) => CrmEntry.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Create a manual department-revenue row. [teamId] is the owning department;
  /// [clientId] is optional. Never carries a project/task reference.
  static Future<String?> createManualEntry({
    required String title,
    required double amount,
    required String createdBy,
    String? teamId,
    String? clientId,
    String? description, // legacy; kept separate from notes
    String? notes, // free-text notes → dedicated `notes` column
    String? dueDate,
    String? entryDate, // yyyy-MM-dd; omitted → DB default CURRENT_DATE
    String? payerName,
  }) async {
    try {
      final res = await _client
          .from('crm_entries')
          .insert({
            'title': title,
            'amount': amount,
            'currency': Money.code,
            'source_type': 'manual',
            'status': 'unpaid',
            'team_id': teamId,
            'client_id': clientId,
            'description': description,
            'notes': notes,
            'due_date': dueDate,
            // Omit entry_date when null so the DB default (today) applies.
            'entry_date': ?entryDate,
            'payer_name': ?payerName,
            'created_by': createdBy,
          })
          .select('id')
          .single();
      return res['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Update editable metadata on a manual entry. Amount is intentionally NOT
  /// updatable here — it must go through [correctAmount] (audited, DB-guarded).
  static Future<String?> updateManualEntry({
    required String id,
    String? title,
    String? description, // legacy; kept separate from notes
    String? notes, // free-text notes → dedicated `notes` column
    String? dueDate,
    String? entryDate, // yyyy-MM-dd
    String? payerName,
  }) async {
    try {
      await _client
          .from('crm_entries')
          .update({
            'title': ?title,
            'description': ?description,
            'notes': ?notes,
            'due_date': ?dueDate,
            'entry_date': ?entryDate,
            'payer_name': ?payerName,
          })
          .eq('id', id);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Cancel (soft-void) an entry — preserves history instead of deleting.
  static Future<String?> cancelEntry(String id) async {
    try {
      await _client
          .from('crm_entries')
          .update({'status': 'cancelled'})
          .eq('id', id);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Payments (audited; enforced admin-only + overpayment-safe at DB level) ──

  static Future<List<CrmPayment>> fetchPayments(String crmEntryId) async {
    try {
      final data = await _client
          .from('crm_payments')
          .select('id, amount_paid, payment_date, status, reference_number, void_reason')
          .eq('crm_entry_id', crmEntryId)
          .order('created_at', ascending: false);
      return (data as List).map((m) => CrmPayment.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Record a payment via the audited RPC. Returns null on success, or the
  /// error message (e.g. overpayment rejected) on failure — surfaced to the UI.
  static Future<String?> recordPayment({
    required String crmEntryId,
    required double amount,
    String? reference,
    String? notes,
    DateTime? date,
  }) async {
    try {
      await _client.rpc('record_crm_payment', params: {
        'p_crm_entry_id': crmEntryId,
        'p_amount': amount,
        'p_payment_date': (date ?? DateTime.now())
            .toIso8601String()
            .substring(0, 10),
        'p_reference': reference,
        'p_notes': notes,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Void a payment (audited). Returns null on success or the error message.
  static Future<String?> voidPayment({
    required String paymentId,
    required String reason,
  }) async {
    try {
      await _client.rpc('void_crm_payment', params: {
        'p_payment_id': paymentId,
        'p_reason': reason,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Correct an invoice/revenue total (audited). The DB rejects any reduction
  /// below the amount already collected. Returns null on success or the error.
  static Future<String?> correctAmount({
    required String crmEntryId,
    required double newAmount,
    required String reason,
  }) async {
    try {
      await _client.rpc('correct_crm_entry_amount', params: {
        'p_crm_entry_id': crmEntryId,
        'p_new_amount': newAmount,
        'p_reason': reason,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}
