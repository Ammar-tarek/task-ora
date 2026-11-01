// lib/features/finance/monthly_revenue_screen.dart
// Monthly revenue experience (Phase C). Admin / Super Admin only (router + RLS).
//   • Month navigator (prev/next) — each month is loaded independently from
//     immutable, dated rows, so previous months are never overwritten.
//   • All-clients table for the month: Total / Paid / Remaining / Status
//     (CHARGES — crm_entries anchored to entry_date), scoped to the active
//     workspace department via WorkspaceScopeNotifier.taskScopeTeamId.
//   • Tapping a client opens their month PAYMENT TRANSACTIONS (crm_payments),
//     kept separate from the charges per the finance model.
// All reads go through FinanceRepository (RLS client) — no service-role.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency.dart';
import 'monthly_revenue.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class MonthlyRevenueScreen extends StatefulWidget {
  const MonthlyRevenueScreen({super.key});

  @override
  State<MonthlyRevenueScreen> createState() => _MonthlyRevenueScreenState();
}

class _MonthlyRevenueScreenState extends State<MonthlyRevenueScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  bool _loading = true;
  List<ClientRevenueRow> _rows = const [];
  MonthlyTotals _totals = const MonthlyTotals(total: 0, paid: 0);
  WorkspaceScopeNotifier? _scope;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scope = context.read<WorkspaceScopeNotifier>()..addListener(_onScope);
      _load();
    });
  }

  @override
  void dispose() {
    _scope?.removeListener(_onScope);
    super.dispose();
  }

  void _onScope() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final teamId = context.read<WorkspaceScopeNotifier>().taskScopeTeamId;
    final entries = await FinanceRepository.fetchMonthlyEntries(
      teamId: teamId,
      year: _year,
      month: _month,
    );
    final rows = MonthlyRevenue.summarize(entries, _year, _month);
    if (mounted) {
      setState(() {
        _rows = rows;
        _totals = MonthlyRevenue.totals(rows);
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WorkspaceScopeNotifier>(); // rebuild on department switch
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Monthly Revenue'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _MonthBar(
            label: '${_monthNames[_month - 1]} $_year',
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          _TotalsStrip(totals: _totals),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const _MessageState(
                        icon: Icons.calendar_month_outlined,
                        title: 'No revenue this month',
                        message:
                            'No client charges are dated in this month for the selected department. Use the arrows to review other months.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _ClientRevenueCard(
                            row: _rows[i],
                            onTap: () => _openClient(_rows[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _openClient(ClientRevenueRow row) {
    if (row.clientId == '__none__') return; // unassigned bucket — nothing to drill into
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientMonthlyPaymentsScreen(
          clientId: row.clientId,
          clientName: row.clientName,
          initialYear: _year,
          initialMonth: _month,
        ),
      ),
    );
  }
}

// ── Per-client month payment transactions ─────────────────────────────────────
class ClientMonthlyPaymentsScreen extends StatefulWidget {
  const ClientMonthlyPaymentsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.initialYear,
    required this.initialMonth,
  });

  final String clientId;
  final String clientName;
  final int initialYear;
  final int initialMonth;

  @override
  State<ClientMonthlyPaymentsScreen> createState() =>
      _ClientMonthlyPaymentsScreenState();
}

class _ClientMonthlyPaymentsScreenState
    extends State<ClientMonthlyPaymentsScreen> {
  late int _year = widget.initialYear;
  late int _month = widget.initialMonth;
  bool _loading = true;
  List<CrmPayment> _payments = const [];
  ClientRevenueRow? _summary; // this client's charge summary for the month

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final teamId = context.read<WorkspaceScopeNotifier>().taskScopeTeamId;
    // Charges (for outstanding) + payment transactions, same month.
    final entries = await FinanceRepository.fetchMonthlyEntries(
      teamId: teamId,
      year: _year,
      month: _month,
    );
    final payments = await FinanceRepository.fetchClientPaymentsInMonth(
      clientId: widget.clientId,
      year: _year,
      month: _month,
    );
    final rows = MonthlyRevenue.summarize(entries, _year, _month)
        .where((r) => r.clientId == widget.clientId)
        .toList();
    if (mounted) {
      setState(() {
        _payments = MonthlyRevenue.paymentsInMonth(payments, _year, _month);
        _summary = rows.isEmpty ? null : rows.first;
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final paidThisMonth =
        _payments.fold<double>(0, (s, p) => s + p.amountPaid);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.clientName)),
      body: Column(
        children: [
          _MonthBar(
            label: '${_monthNames[_month - 1]} $_year',
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          // Charges summary for the month (separate from transactions below).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _TotalChip(
                    label: 'Charged',
                    value: _summary?.total ?? 0,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                _TotalChip(
                    label: 'Payments',
                    value: paidThisMonth,
                    color: Colors.green),
                const SizedBox(width: 8),
                _TotalChip(
                    label: 'Outstanding',
                    value: _summary?.remaining ?? 0,
                    color: AppColors.gold),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : _payments.isEmpty
                    ? const _MessageState(
                        icon: Icons.payments_outlined,
                        title: 'No payments this month',
                        message:
                            'This client made no payment transactions in this month.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _payments.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _PaymentCard(payment: _payments[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── shared widgets ────────────────────────────────────────────────────────────
class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.label, required this.onPrev, required this.onNext});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: onPrev,
          ),
          Text(label, style: AppTextStyles.headlineSm.copyWith(fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.totals});
  final MonthlyTotals totals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          _TotalChip(label: 'Total', value: totals.total, color: AppColors.primary),
          const SizedBox(width: 8),
          _TotalChip(label: 'Received', value: totals.paid, color: Colors.green),
          const SizedBox(width: 8),
          _TotalChip(label: 'Remaining', value: totals.remaining, color: AppColors.gold),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(Money.egp(value),
                style: AppTextStyles.bodyMd
                    .copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ClientRevenueCard extends StatelessWidget {
  const _ClientRevenueCard({required this.row, required this.onTap});
  final ClientRevenueRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(row.clientName,
                      style: AppTextStyles.bodyMd
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                _StatusPill(status: row.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _amt('Total', row.total, AppColors.onSurface),
                _amt('Paid', row.paid, Colors.green),
                _amt('Remaining', row.remaining, AppColors.gold),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amt(String label, double v, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(Money.egp(v),
                style: AppTextStyles.dataSm.copyWith(color: color)),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PaymentStatus.paid => Colors.green,
      PaymentStatus.partial => AppColors.gold,
      PaymentStatus.unpaid => AppColors.error,
      PaymentStatus.none => AppColors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.label,
          style: AppTextStyles.bodySm
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});
  final CrmPayment payment;

  @override
  Widget build(BuildContext context) {
    final date = payment.paymentDate.length >= 10
        ? payment.paymentDate.substring(0, 10)
        : payment.paymentDate;
    final method = (payment.paymentMethod ?? '').isEmpty
        ? '—'
        : payment.paymentMethod!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Money.egp(payment.amountPaid),
                    style: AppTextStyles.bodyMd
                        .copyWith(fontWeight: FontWeight.w700, color: Colors.green)),
                const SizedBox(height: 2),
                Text('$date · $method',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
                if ((payment.reference ?? '').isNotEmpty)
                  Text('Ref: ${payment.reference}',
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.payments_outlined, color: AppColors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.outlineVariant),
            const SizedBox(height: 16),
            Text(title,
                style: AppTextStyles.headlineSm
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
