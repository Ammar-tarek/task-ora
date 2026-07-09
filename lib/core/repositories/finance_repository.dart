// lib/core/repositories/finance_repository.dart

import '../services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrmEntry
// ─────────────────────────────────────────────────────────────────────────────

class CrmEntry {
  final String id;
  final String clientName;
  final String title;
  final double amount;
  final double paidAmount;
  final String status;      // 'unpaid' | 'partial' | 'paid' | 'overdue'
  final String sourceType;  // 'task' | 'room_booking' | 'manual'
  final String? dueDate;
  final String? invoiceNumber;
  final String currency;

  const CrmEntry({
    required this.id,
    required this.clientName,
    required this.title,
    required this.amount,
    required this.paidAmount,
    required this.status,
    required this.sourceType,
    this.dueDate,
    this.invoiceNumber,
    required this.currency,
  });

  factory CrmEntry.fromMap(Map<String, dynamic> m) {
    final client = m['client'] as Map<String, dynamic>?;
    return CrmEntry(
      id:            m['id'] as String,
      clientName:    client?['company_name'] as String? ?? 'Unknown Client',
      title:         m['title'] as String? ?? '',
      amount:        (m['amount'] as num?)?.toDouble() ?? 0,
      paidAmount:    (m['paid_amount'] as num?)?.toDouble() ?? 0,
      status:        m['status'] as String? ?? 'unpaid',
      sourceType:    m['source_type'] as String? ?? 'manual',
      dueDate:       m['due_date'] as String?,
      invoiceNumber: m['invoice_number'] as String?,
      currency:      m['currency'] as String? ?? 'USD',
    );
  }

  double get outstanding => amount - paidAmount;
  String get statusLabel {
    switch (status) {
      case 'unpaid':  return 'Unpaid';
      case 'partial': return 'Partial';
      case 'paid':    return 'Paid';
      case 'overdue': return 'Overdue';
      default:        return status;
    }
  }
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
  double get netProfit    => grossRevenue - totalExpenses;
  double get outstanding  => totalInvoiced - totalPaid;
}

// ─────────────────────────────────────────────────────────────────────────────
// FinanceRepository
// ─────────────────────────────────────────────────────────────────────────────

class FinanceRepository {
  static final _admin = SupabaseService.adminClient;

  // ── CRM entries ───────────────────────────────────────────────────────────

  static Future<List<CrmEntry>> fetchCrmEntries({String? status}) async {
    try {
      final base = _admin
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
    double taskRevenue    = 0;
    double meetingRevenue = 0;
    double totalExpenses  = 0;
    double totalInvoiced  = 0;
    double totalPaid      = 0;
    int    pendingInvoices = 0;
    int    overdueCount    = 0;

    // If scoped to a department, resolve client IDs for CRM filtering
    List<String>? scopedClientIds;
    if (clientType != null) {
      try {
        final rows = await _admin
            .from('client_profiles')
            .select('id')
            .or('client_type.eq.$clientType,client_type.eq.both');
        scopedClientIds = (rows as List)
            .map((r) => r['id'] as String)
            .toList();
      } catch (_) {
        scopedClientIds = [];
      }
    }

    // Only `tasks` and `profiles` carry team_id. Events/expenses are scoped
    // through the team's members (created_by / recorded_by).
    List<String>? memberIds;
    if (teamId != null) {
      try {
        final rows = await _admin.from('profiles').select('id').eq('team_id', teamId);
        memberIds = (rows as List).map((r) => r['id'] as String).toList();
      } catch (_) {
        memberIds = [];
      }
    }

    await Future.wait([
      // Task costs (tasks have team_id)
      () async {
        try {
          var q = _admin.from('tasks').select('cost').not('cost', 'is', null);
          if (teamId != null) q = q.eq('team_id', teamId);
          final rows = await q;
          taskRevenue = (rows as List)
              .fold(0.0, (s, r) => s + ((r['cost'] as num?)?.toDouble() ?? 0));
        } catch (_) {}
      }(),
      // Event / meeting costs (scoped by creator's team membership)
      () async {
        try {
          if (memberIds != null && memberIds.isEmpty) return;
          var q = _admin.from('events').select('cost').not('cost', 'is', null);
          if (memberIds != null) q = q.inFilter('created_by', memberIds);
          final rows = await q;
          meetingRevenue = (rows as List)
              .fold(0.0, (s, r) => s + ((r['cost'] as num?)?.toDouble() ?? 0));
        } catch (_) {}
      }(),
      // Expenses (scoped by recorder's team membership)
      () async {
        try {
          if (memberIds != null && memberIds.isEmpty) return;
          var q = _admin.from('expenses').select('amount');
          if (memberIds != null) q = q.inFilter('recorded_by', memberIds);
          final rows = await q;
          totalExpenses = (rows as List)
              .fold(0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
        } catch (_) {}
      }(),
      // CRM invoices
      () async {
        try {
          var q = _admin.from('crm_entries').select('amount, paid_amount, status');
          if (scopedClientIds != null) {
            if (scopedClientIds.isEmpty) return; // no clients → no invoices
            q = q.inFilter('client_id', scopedClientIds);
          }
          final rows = await q;
          for (final r in rows as List) {
            totalInvoiced += (r['amount'] as num?)?.toDouble() ?? 0;
            totalPaid     += (r['paid_amount'] as num?)?.toDouble() ?? 0;
            final st = r['status'] as String? ?? '';
            if (st != 'paid') pendingInvoices++;
            if (st == 'overdue') overdueCount++;
          }
        } catch (_) {}
      }(),
    ]);

    return FinanceSummary(
      taskRevenue:    taskRevenue,
      meetingRevenue: meetingRevenue,
      totalExpenses:  totalExpenses,
      totalInvoiced:  totalInvoiced,
      totalPaid:      totalPaid,
      pendingInvoices: pendingInvoices,
      overdueCount:   overdueCount,
    );
  }

  // ── Monthly revenue breakdown (last 6 months, tasks + events) ────────────
  // Pass [teamId] to scope to one team (manager view).

  static Future<List<Map<String, dynamic>>> fetchMonthlyBreakdown({
    String? teamId,
  }) async {
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun',
                        'Jul','Aug','Sep','Oct','Nov','Dec'];
    final now = DateTime.now();

    // Build ordered map for the last 6 months (oldest → newest)
    final orderedKeys = <String>[];
    final months      = <String, double>{};
    for (int i = 5; i >= 0; i--) {
      final dt  = DateTime(now.year, now.month - i);
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
        final rows = await _admin.from('profiles').select('id').eq('team_id', teamId);
        memberIds = (rows as List).map((r) => r['id'] as String).toList();
      } catch (_) {
        memberIds = [];
      }
    }

    await Future.wait([
      () async {
        try {
          var q = _admin.from('tasks').select('cost, created_at').not('cost', 'is', null);
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
          var q = _admin.from('events').select('cost, start_time').not('cost', 'is', null);
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

  static Future<List<Map<String, dynamic>>> fetchTopClients({int limit = 5}) async {
    try {
      final rows = await _admin
          .from('tasks')
          .select('client_id, cost, client:client_profiles(company_name)')
          .not('client_id', 'is', null)
          .not('cost', 'is', null);

      final Map<String, Map<String, dynamic>> map = {};
      for (final r in rows as List) {
        final clientId = r['client_id'] as String;
        final name     = (r['client'] as Map<String, dynamic>?)?['company_name'] as String? ?? 'Unknown';
        final cost     = (r['cost'] as num?)?.toDouble() ?? 0;
        map.putIfAbsent(clientId, () => {'name': name, 'revenue': 0.0, 'tasks': 0});
        map[clientId]!['revenue'] = (map[clientId]!['revenue'] as double) + cost;
        map[clientId]!['tasks']   = (map[clientId]!['tasks'] as int) + 1;
      }

      return (map.values.toList()
            ..sort((a, b) =>
                (b['revenue'] as double).compareTo(a['revenue'] as double)))
          .take(limit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Expense breakdown by category ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchExpensesByCategory() async {
    try {
      final rows = await _admin
          .from('expenses')
          .select('amount, category:expense_categories(name)');

      final Map<String, double> cats = {};
      double total = 0;
      for (final r in rows as List) {
        final name   = (r['category'] as Map<String, dynamic>?)?['name'] as String? ?? 'Other';
        final amount = (r['amount'] as num?)?.toDouble() ?? 0;
        cats[name] = (cats[name] ?? 0) + amount;
        total      += amount;
      }

      if (total == 0) return [];

      return (cats.entries.map((e) => {
        'label': e.key,
        'value': e.value / total * 100,
        'amount': e.value,
      }).toList()
        ..sort((a, b) => (b['value'] as double).compareTo(a['value'] as double)));
    } catch (_) {
      return [];
    }
  }

  // ── Record a payment ──────────────────────────────────────────────────────

  static Future<void> recordPayment({
    required String crmEntryId,
    required String clientId,
    required double amount,
    required String recordedBy,
    String? referenceNumber,
  }) async {
    try {
      await _admin.from('crm_payments').insert({
        'crm_entry_id':     crmEntryId,
        'client_id':        clientId,
        'amount_paid':      amount,
        'payment_date':     DateTime.now().toIso8601String().substring(0, 10),
        'recorded_by':      recordedBy,
        'reference_number': referenceNumber,
      });
    } catch (_) {}
  }
}
