// lib/features/finance/department_revenue_sheet_screen.dart
// Excel-style department revenue sheet (the primary Finance screen). Admin /
// Super Admin only — Managers and Employees are blocked by the router and RLS.
//
// Scope & rules:
//  * Shows MANUAL revenue entries only (crm_entries.source_type = 'manual').
//    Task/booking-generated CRM records live with the client, not here.
//  * The DEPARTMENT in view is the active workspace (set via the workspace
//    header's "Switch Department"); there is no in-table department picker.
//    New entries inherit the active department automatically.
//  * The primary table has exactly seven columns (see [columnLabels]). Row
//    actions (payment / void / correct / edit / cancel) live in a contextual
//    menu opened by tapping the row — not an actions column.
//  * Payments, voids and amount corrections all go through audited,
//    overpayment-safe database RPCs (never direct writes).
//  * Currency is EGP everywhere.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/constants/departments.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/services/revenue_create_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency.dart';

class DepartmentRevenueSheetScreen extends StatefulWidget {
  const DepartmentRevenueSheetScreen({super.key});

  /// The seven primary-table columns, in display order. Exposed so the exact
  /// column set is unit-testable without building the whole screen.
  static const List<String> columnLabels = [
    'Date',
    'Entry / Description',
    'Client / Payer Name',
    'Total Price',
    'Amount Received',
    'Remaining Balance',
    'Notes',
  ];

  @override
  State<DepartmentRevenueSheetScreen> createState() =>
      _DepartmentRevenueSheetScreenState();
}

class _DepartmentRevenueSheetScreenState
    extends State<DepartmentRevenueSheetScreen> {
  List<CrmEntry> _entries = [];
  bool _loading = true;
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
    // The displayed department is the active workspace. For a global user this
    // is: null → All Departments (everything), a real team id → that
    // department, or the no-team sentinel → match nothing (never leak all).
    final teamId = context.read<WorkspaceScopeNotifier>().taskScopeTeamId;
    final entries = await FinanceRepository.fetchManualRevenue(teamId: teamId);
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  double get _totalAmount => _entries.fold(0.0, (s, e) => s + e.amount);
  double get _totalPaid => _entries.fold(0.0, (s, e) => s + e.paidAmount);
  double get _totalOutstanding =>
      _entries.fold(0.0, (s, e) => s + e.outstanding);

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    context.watch<WorkspaceScopeNotifier>(); // rebuild on department switch
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Department Revenue'),
        actions: [
          IconButton(
            tooltip: 'Analytics',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.push('/finance/analytics'),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add revenue'),
        onPressed: _openAddDialog,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(
              children: [
                _buildTotals(),
                const Divider(height: 1),
                Expanded(
                  child: _entries.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _buildTable(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTotals() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _TotalChip(label: 'Total', value: _totalAmount, color: AppColors.primary),
          const SizedBox(width: 8),
          _TotalChip(
            label: 'Received',
            value: _totalPaid,
            color: const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          _TotalChip(
            label: 'Remaining',
            value: _totalOutstanding,
            color: _totalOutstanding > 0
                ? AppColors.error
                : AppColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return DataTable(
      headingRowColor: WidgetStatePropertyAll(
        AppColors.primary.withValues(alpha: 0.06),
      ),
      columnSpacing: 22,
      showCheckboxColumn: false,
      columns: const [
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Entry / Description')),
        DataColumn(label: Text('Client / Payer Name')),
        DataColumn(label: Text('Total Price'), numeric: true),
        DataColumn(label: Text('Amount Received'), numeric: true),
        DataColumn(label: Text('Remaining Balance'), numeric: true),
        DataColumn(label: Text('Notes')),
      ],
      rows: _entries.map((e) {
        final cancelled = e.status == 'cancelled';
        final faded = cancelled ? AppColors.onSurfaceVariant : null;
        return DataRow(
          onSelectChanged: (_) => _openRowActions(e),
          cells: [
            DataCell(Text(e.displayDate, style: TextStyle(color: faded))),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  cancelled ? '${e.title} (cancelled)' : e.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: faded,
                    decoration:
                        cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
            DataCell(Text(e.payerDisplay, style: TextStyle(color: faded))),
            DataCell(Text(Money.egp(e.amount), style: TextStyle(color: faded))),
            DataCell(Text(Money.egp(e.paidAmount), style: TextStyle(color: faded))),
            DataCell(
              Text(Money.egp(e.outstanding), style: TextStyle(color: faded)),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  e.notesDisplay.isEmpty ? '—' : e.notesDisplay,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: e.notesDisplay.isEmpty
                        ? AppColors.onSurfaceVariant
                        : faded,
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No manual revenue in this department yet.\n'
          'Tap "Add revenue" to record an entry.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }

  // ── Row actions (contextual menu — opened by tapping a row) ─────────────────
  void _openRowActions(CrmEntry e) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(e.title,
                  style: AppTextStyles.labelMd
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Status: ${e.statusLabel}',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            if (e.status != 'cancelled' && e.outstanding > 0)
              ListTile(
                leading: const Icon(Icons.payments_outlined, color: AppColors.gold),
                title: const Text('Record payment'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openRecordPayment(e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Payments & voids'),
              onTap: () {
                Navigator.pop(ctx);
                _openPayments(e);
              },
            ),
            if (e.status != 'cancelled')
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Correct amount'),
                subtitle: const Text('Audited — cannot go below collected'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCorrectAmount(e);
                },
              ),
            if (e.status != 'cancelled')
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit details'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAddDialog(edit: e);
                },
              ),
            if (e.status != 'cancelled')
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: AppColors.error),
                title: Text('Cancel entry',
                    style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmCancel(e);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Add / edit entry ─────────────────────────────────────────────────────────
  Future<void> _openAddDialog({CrmEntry? edit}) async {
    final titleCtrl = TextEditingController(text: edit?.title ?? '');
    final notesCtrl = TextEditingController(text: edit?.notes ?? '');
    final payerCtrl = TextEditingController(text: edit?.payerName ?? '');
    final amountCtrl = TextEditingController(
      text: edit != null ? edit.amount.toStringAsFixed(2) : '',
    );
    String? clientId = edit?.clientId;
    DateTime entryDate =
        DateTime.tryParse(edit?.entryDate ?? '') ?? DateTime.now();

    // Department is the ACTIVE WORKSPACE — never chosen in the dialog. On edit
    // the entry keeps its own department (ownership stays stable).
    final scope = context.read<WorkspaceScopeNotifier>();
    final profile = context.read<AuthNotifier>().profile;
    final activeTeamId = edit?.teamId ??
        (profile != null
            ? RevenueCreateScope.departmentTeamIdFor(
                profile,
                activeTeamId: scope.activeDepartmentTeamId,
              )
            : scope.activeDepartmentTeamId);
    final deptLabel = edit != null
        ? (scope.state.departmentForTeamId(edit.teamId)?.label ??
            'This department')
        : (scope.effectiveDepartment?.label ?? 'All Departments');

    final clients = await ClientRepository.fetchClients();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          title: Text(edit == null ? 'Add revenue' : 'Edit revenue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Read-only department indicator (active workspace).
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    isDense: true,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.workspaces_outline,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(child: Text(deptLabel)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date *',
                    isDense: true,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(_fmtDate(entryDate))),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Pick'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: entryDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => entryDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: clientId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Client (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No client (internal)'),
                    ),
                    ...clients.map((c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.companyName,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: edit != null
                      ? null
                      : (v) => setLocal(() => clientId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: payerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Payer name (optional)',
                    helperText: 'Free text — who paid',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Entry / Description *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                if (edit == null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total Price *',
                      prefixText: 'EGP ',
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Total: ${Money.egp(edit.amount)} — change it via "Correct amount".',
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  _snack('Entry / Description is required.', error: true);
                  return;
                }
                String? err;
                if (edit == null) {
                  // Internal (no client) revenue needs a department so the DB
                  // owner CHECK is satisfied. All-Departments has none.
                  if (activeTeamId == null && clientId == null) {
                    _snack(
                      'Open a specific department (or pick a client) to add revenue.',
                      error: true,
                    );
                    return;
                  }
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (amount == null || amount <= 0) {
                    _snack('Enter a valid total price.', error: true);
                    return;
                  }
                  final uid = profile?.id ?? '';
                  final id = await FinanceRepository.createManualEntry(
                    title: title,
                    amount: amount,
                    createdBy: uid,
                    teamId: activeTeamId,
                    clientId: clientId,
                    entryDate: _fmtDate(entryDate),
                    payerName: payerCtrl.text.trim().isEmpty
                        ? null
                        : payerCtrl.text.trim(),
                    notes:
                        notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  err = id == null ? 'Failed to create entry.' : null;
                } else {
                  err = await FinanceRepository.updateManualEntry(
                    id: edit.id,
                    title: title,
                    notes: notesCtrl.text.trim(),
                    entryDate: _fmtDate(entryDate),
                    payerName: payerCtrl.text.trim(),
                  );
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (err != null) {
                  _snack(err, error: true);
                } else {
                  _snack(edit == null ? 'Revenue added.' : 'Updated.');
                  _load();
                }
              },
              child: Text(edit == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Record payment ───────────────────────────────────────────────────────────
  Future<void> _openRecordPayment(CrmEntry e) async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Record payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Remaining: ${Money.egp(e.outstanding)}',
                style: AppTextStyles.bodySm),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount *',
                prefixText: 'EGP ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                _snack('Enter a valid amount.', error: true);
                return;
              }
              final err = await FinanceRepository.recordPayment(
                crmEntryId: e.id,
                amount: amount,
                reference: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                _snack(err, error: true);
              } else {
                _snack('Payment recorded.');
                _load();
              }
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  // ── Correct amount ─────────────────────────────────────────────────────────────
  Future<void> _openCorrectAmount(CrmEntry e) async {
    final amountCtrl = TextEditingController(text: e.amount.toStringAsFixed(2));
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Correct amount'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Already collected: ${Money.egp(e.paidAmount)}',
                style: AppTextStyles.bodySm),
            const SizedBox(height: 4),
            Text(
              'The new total cannot be below the collected amount. To reduce '
              'further, void payments first.',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'New total *',
                prefixText: 'EGP ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason *'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim());
              final reason = reasonCtrl.text.trim();
              if (amount == null || amount < 0) {
                _snack('Enter a valid amount.', error: true);
                return;
              }
              if (reason.isEmpty) {
                _snack('A reason is required.', error: true);
                return;
              }
              final err = await FinanceRepository.correctAmount(
                crmEntryId: e.id,
                newAmount: amount,
                reason: reason,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                _snack(err, error: true);
              } else {
                _snack('Amount corrected.');
                _load();
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Payments list + void ───────────────────────────────────────────────────────
  Future<void> _openPayments(CrmEntry e) async {
    final payments = await FinanceRepository.fetchPayments(e.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payments — ${e.title}',
                  style: AppTextStyles.labelMd
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (payments.isEmpty)
                Text('No payments recorded.',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant))
              else
                ...payments.map((p) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        Money.egp(p.amountPaid),
                        style: TextStyle(
                          decoration:
                              p.isVoided ? TextDecoration.lineThrough : null,
                          color: p.isVoided ? AppColors.onSurfaceVariant : null,
                        ),
                      ),
                      subtitle: Text(
                        p.isVoided
                            ? 'Voided — ${p.voidReason ?? ''}'
                            : p.paymentDate,
                      ),
                      trailing: p.isVoided
                          ? const Text('VOIDED')
                          : TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _confirmVoid(e, p);
                              },
                              child: Text('Void',
                                  style: TextStyle(color: AppColors.error)),
                            ),
                    )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmVoid(CrmEntry e, CrmPayment p) async {
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Void payment'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) {
                _snack('A reason is required.', error: true);
                return;
              }
              final err = await FinanceRepository.voidPayment(
                paymentId: p.id,
                reason: reason,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                _snack(err, error: true);
              } else {
                _snack('Payment voided.');
                _load();
              }
            },
            child: const Text('Void'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(CrmEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Cancel entry?'),
        content: Text(
          'Mark "${e.title}" as cancelled? Payment history is preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel entry'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final err = await FinanceRepository.cancelEntry(e.id);
      if (!mounted) return;
      if (err != null) {
        _snack(err, error: true);
      } else {
        _snack('Entry cancelled.');
        _load();
      }
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : null,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              Money.egpCompact(value),
              style: AppTextStyles.dataMd
                  .copyWith(color: color, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
