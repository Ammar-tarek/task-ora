// lib/features/expenses/daily_expenses_screen.dart
// Standalone CENTRAL COMPANY EXPENSES page (Admin only). Shows the company's
// central cash balance and a deposit/expense ledger. Fully isolated from
// Department Finance and the shared `expenses` table — it reads/writes only the
// company_ledger via CompanyLedgerRepository (admin-only, atomic, server-side).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/repositories/company_ledger_repository.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_theme.dart';

class DailyExpensesScreen extends StatefulWidget {
  const DailyExpensesScreen({super.key});
  @override
  State<DailyExpensesScreen> createState() => _DailyExpensesScreenState();
}

class _DailyExpensesScreenState extends State<DailyExpensesScreen> {
  List<LedgerEntry> _all = []; // all rows, chronological, running balance set
  bool _loading = true;

  // Selected reporting month — defaults to the current calendar month.
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Balance = collected department revenue − company expenses. Deposits come
    // from crm_payments (one per installment); crm_entries carries status, so
    // refresh on any of the three changing.
    RealtimeService.instance.listen(
      const ['company_ledger', 'crm_payments', 'crm_entries'],
      _onRealtime,
    );
  }

  void _onRealtime() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await CompanyLedgerRepository.fetchAll();
    if (mounted) {
      setState(() {
        _all = all;
        _loading = false;
      });
    }
  }

  // Selected-month slice, newest first for display.
  List<LedgerEntry> get _monthEntries {
    final m = CompanyLedgerRepository.inMonth(_all, _year, _month);
    return m.reversed.toList();
  }

  double get _balance => CompanyLedgerRepository.balanceOf(_all);
  double get _monthExpenses =>
      CompanyLedgerRepository.monthlyExpenseTotal(_all, _year, _month);
  int get _monthCount =>
      CompanyLedgerRepository.monthlyExpenseCount(_all, _year, _month);

  bool get _isCurrentOrPast {
    final now = DateTime.now();
    return _year < now.year || (_year == now.year && _month <= now.month);
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
  }

  void _nextMonth() {
    if (_isCurrentOrPast) {
      // only move forward up to the current month
      final now = DateTime.now();
      if (_year == now.year && _month == now.month) return;
      setState(() {
        if (_month == 12) {
          _month = 1;
          _year++;
        } else {
          _month++;
        }
      });
    }
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _goBack() {
    // Company Expenses is opened from the departments page via context.go
    // (no back stack), so always return to the departments workspace page.
    context.go(AppRoutes.workspaces);
  }

  @override
  Widget build(BuildContext context) {
    context.select<LocaleController, Locale>((l) => l.locale);
    final isAdmin = context.select<AuthNotifier, bool>(
      (a) => a.profile?.isAdmin == true,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: _goBack,
        ),
        title: const Text('Company Expenses'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (isAdmin)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'reset') _confirmReset();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt, size: 18, color: AppColors.statusHigh),
                      SizedBox(width: 8),
                      Text('Reset balance to 0'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: !isAdmin
          ? const _AdminOnlyNotice()
          : _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                )
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildMonthNav(),
                      const SizedBox(height: 16),
                      _buildBalanceCard(),
                      const SizedBox(height: 16),
                      _buildActions(),
                      const SizedBox(height: 20),
                      _buildLedger(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildMonthNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.gold),
          onPressed: _prevMonth,
          tooltip: 'Previous month',
        ),
        Text(
          '${_monthNames[_month - 1]} $_year',
          style: AppTextStyles.headlineSm,
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: (_year == DateTime.now().year && _month == DateTime.now().month)
                ? AppColors.outlineVariant
                : AppColors.gold,
          ),
          onPressed: _nextMonth,
          tooltip: 'Next month',
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            'AVAILABLE COMPANY BALANCE',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onPrimary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_balance.toStringAsFixed(2)} EGP',
            style: AppTextStyles.dataLg.copyWith(
              color: AppColors.gold,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniStat(
                label: 'THIS MONTH',
                value: '${_monthExpenses.toStringAsFixed(2)} EGP',
              ),
              Container(
                width: 1,
                height: 32,
                color: AppColors.onPrimary.withValues(alpha: 0.2),
              ),
              _MiniStat(
                label: 'TRANSACTIONS',
                value: '$_monthCount',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    // Deposits come from collected department revenue (recorded in the
    // department revenue sheets), so there is no manual "Add Funds" here —
    // only company expenses are entered on this page.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showRecordExpense,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppColors.gold),
        label: const Text('Record Expense', style: TextStyle(color: AppColors.gold)),
      ),
    );
  }

  Widget _buildLedger() {
    final entries = _monthEntries;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.outlineVariant),
              const SizedBox(height: 12),
              Text('No transactions this month', style: AppTextStyles.labelMd),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LEDGER', style: AppTextStyles.labelCaps),
        const SizedBox(height: 8),
        // Horizontal scroll keeps the table readable on narrow phones.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: DataTable(
              columnSpacing: 20,
              headingRowColor: WidgetStatePropertyAll(
                AppColors.surfaceContainerLowest,
              ),
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Department')),
                DataColumn(label: Text('Recorded By')),
                DataColumn(label: Text('Amount'), numeric: true),
                DataColumn(label: Text('Balance'), numeric: true),
              ],
              rows: entries.map((e) {
                final sign = e.isDeposit ? '+' : '−';
                final color = e.isDeposit ? AppColors.statusDone : AppColors.statusHigh;
                return DataRow(cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(e.date, style: AppTextStyles.bodySm),
                        if (e.timeLabel.isNotEmpty)
                          Text(
                            e.timeLabel,
                            style: AppTextStyles.dataSm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  DataCell(_TypePill(isDeposit: e.isDeposit)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        e.description.isEmpty ? '—' : e.description,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm,
                      ),
                    ),
                  ),
                  DataCell(Text(
                    (e.department?.trim().isNotEmpty ?? false) ? e.department! : '—',
                    style: AppTextStyles.bodySm,
                  )),
                  DataCell(Text(
                    (e.recordedBy?.trim().isNotEmpty ?? false) ? e.recordedBy! : '—',
                    style: AppTextStyles.bodySm,
                  )),
                  DataCell(Text(
                    '$sign${e.amount.toStringAsFixed(2)}',
                    style: AppTextStyles.dataSm.copyWith(color: color),
                  )),
                  DataCell(Text(
                    e.balanceAfter.toStringAsFixed(2),
                    style: AppTextStyles.dataSm,
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showRecordExpense() => _showTxnDialog();

  /// Reset the available company balance to zero. Records a single balancing
  /// "Balance reset" expense (ledger history is kept). Admin-only + confirmed.
  Future<void> _confirmReset() async {
    if (_balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balance is already zero — nothing to reset.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Reset company balance?'),
        content: Text(
          'This records a "Balance reset" expense of '
          '${_balance.toStringAsFixed(2)} EGP so the available balance becomes 0. '
          'The ledger history is kept. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusHigh),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await CompanyLedgerRepository.resetBalanceToZero(
      currentBalance: _balance,
      clientToken: CompanyLedgerRepository.newToken(),
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade800),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Balance reset to 0.')),
    );
    _load();
  }

  Future<void> _showTxnDialog() async {
    final token = CompanyLedgerRepository.newToken(); // one per attempt
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TxnDialog(
        clientToken: token,
        currentBalance: _balance,
      ),
    );
    if (saved == true) _load();
  }
}

// ── Mini stat (inside the balance card) ───────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            color: AppColors.onPrimary.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary),
        ),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isDeposit});
  final bool isDeposit;

  @override
  Widget build(BuildContext context) {
    final color = isDeposit ? AppColors.statusDone : AppColors.statusHigh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isDeposit ? 'Deposit' : 'Expense',
        style: AppTextStyles.bodySm.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _AdminOnlyNotice extends StatelessWidget {
  const _AdminOnlyNotice();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 56, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text('Company Expenses is admin-only.', style: AppTextStyles.labelMd),
        ],
      ),
    );
  }
}

// ── Add Funds / Record Expense dialog ─────────────────────────────────────────

class _TxnDialog extends StatefulWidget {
  const _TxnDialog({
    required this.clientToken,
    required this.currentBalance,
  });
  final String clientToken;
  final double currentBalance;

  @override
  State<_TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends State<_TxnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final amount = double.parse(_amountCtrl.text.trim());
    final date = _date.toIso8601String().substring(0, 10);
    final desc = _descCtrl.text.trim();
    final err = await CompanyLedgerRepository.recordExpense(
      amount: amount,
      date: date,
      description: desc,
      clientToken: widget.clientToken,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      title: const Text('Record Expense'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Available: ${widget.currentBalance.toStringAsFixed(2)} EGP',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP)',
                    prefixText: 'EGP ',
                  ),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null) return 'Enter a valid number';
                    if (n <= 0) return 'Amount must be greater than zero';
                    if (n > widget.currentBalance) {
                      return 'Exceeds available balance';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Date: ${_date.day}/${_date.month}/${_date.year}',
                    style: AppTextStyles.bodyMd,
                  ),
                  trailing: const Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.gold,
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Record Expense'),
        ),
      ],
    );
  }
}
