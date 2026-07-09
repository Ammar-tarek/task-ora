// lib/features/clients/client_finance_screen.dart
// Per-client finance view: tasks, calendar meetings (with cost), and CRM entries.

import 'package:flutter/material.dart';
import '../../core/models/client_model.dart';
import '../../core/models/task_model.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';

class ClientFinanceScreen extends StatefulWidget {
  const ClientFinanceScreen({super.key, required this.clientId});
  final String clientId;

  @override
  State<ClientFinanceScreen> createState() => _ClientFinanceScreenState();
}

class _ClientFinanceScreenState extends State<ClientFinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  ClientModel? _client;
  List<TaskModel> _tasks = [];
  List<CalEventData> _events = [];
  List<CrmEntry> _crm = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ClientRepository.fetchClientById(widget.clientId),
      ClientRepository.fetchClientTasks(widget.clientId),
      ClientRepository.fetchClientEvents(widget.clientId),
      ClientRepository.fetchClientCrmEntries(widget.clientId),
    ]);
    if (mounted) {
      setState(() {
        _client = results[0] as ClientModel?;
        _tasks  = results[1] as List<TaskModel>;
        _events = results[2] as List<CalEventData>;
        _crm    = results[3] as List<CrmEntry>;
        _loading = false;
      });
    }
  }

  // ── Financial summary ───────────────────────────────────────────────────────

  double get _totalTaskCost =>
      _tasks.fold(0, (s, t) => s + (t.cost ?? 0));

  double get _totalMeetingCost =>
      _events.fold(0, (s, e) => s + (e.cost ?? 0));

  double get _totalInvoiced =>
      _crm.fold(0, (s, e) => s + e.amount);

  double get _totalPaid =>
      _crm.fold(0, (s, e) => s + e.paidAmount);

  @override
  Widget build(BuildContext context) {
    final name = _client?.companyName ?? 'Client';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(name),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Finance'),
            Tab(text: 'Tasks'),
            Tab(text: 'Meetings'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _client == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.link_off, size: 48, color: AppColors.outlineVariant),
                      const SizedBox(height: 16),
                      Text('Account not linked',
                          style: AppTextStyles.headlineSm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text(
                        'Your account is not linked to a client profile.\n'
                        'Please contact your administrator.',
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                )
              : TabBarView(
              controller: _tab,
              children: [
                _FinanceTab(
                  crm: _crm,
                  tasks: _tasks,
                  totalTaskCost: _totalTaskCost,
                  totalMeetingCost: _totalMeetingCost,
                  totalInvoiced: _totalInvoiced,
                  totalPaid: _totalPaid,
                ),
                _TasksTab(tasks: _tasks),
                _MeetingsTab(events: _events),
              ],
            ),
    );
  }
}

// ── Finance tab ────────────────────────────────────────────────────────────────
class _FinanceTab extends StatelessWidget {
  const _FinanceTab({
    required this.crm,
    required this.tasks,
    required this.totalTaskCost,
    required this.totalMeetingCost,
    required this.totalInvoiced,
    required this.totalPaid,
  });
  final List<CrmEntry> crm;
  final List<TaskModel> tasks;
  final double totalTaskCost, totalMeetingCost, totalInvoiced, totalPaid;

  double get _totalRevenue => totalTaskCost + totalMeetingCost + totalInvoiced;
  double get _outstanding  => totalInvoiced - totalPaid;

  @override
  Widget build(BuildContext context) {
    final tasksWithCost = tasks.where((t) => (t.cost ?? 0) > 0).toList()
      ..sort((a, b) => (b.cost ?? 0).compareTo(a.cost ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Total revenue hero ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TOTAL REVENUE',
                style: AppTextStyles.labelCaps.copyWith(color: Colors.white54)),
            const SizedBox(height: 6),
            Text('EGP ${_totalRevenue.toStringAsFixed(2)}',
                style: AppTextStyles.dataLg.copyWith(
                    color: AppColors.gold, fontSize: 32,
                    fontWeight: FontWeight.w700)),
            const Divider(color: Colors.white24, height: 24),
            Row(children: [
              Expanded(child: _SummaryItem(
                  label: 'Task Services',
                  value: 'EGP ${totalTaskCost.toStringAsFixed(0)}')),
              Expanded(child: _SummaryItem(
                  label: 'Meetings',
                  value: 'EGP ${totalMeetingCost.toStringAsFixed(0)}')),
              Expanded(child: _SummaryItem(
                  label: 'Invoiced',
                  value: 'EGP ${totalInvoiced.toStringAsFixed(0)}')),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Invoice status strip ────────────────────────────────────
        Row(children: [
          Expanded(child: _StatCard(
              label: 'Paid', value: 'EGP ${totalPaid.toStringAsFixed(0)}',
              color: const Color(0xFF81C784))),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(
              label: 'Outstanding', value: 'EGP ${_outstanding.toStringAsFixed(0)}',
              color: _outstanding > 0 ? AppColors.error : AppColors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 24),

        // ── Task cost breakdown ─────────────────────────────────────
        if (tasksWithCost.isNotEmpty) ...[
          Text('Task Services', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          ...tasksWithCost.map((t) => _TaskCostRow(task: t)),
          const SizedBox(height: 24),
        ],

        // ── CRM invoices ────────────────────────────────────────────
        Text('Invoices & Payments', style: AppTextStyles.headlineSm),
        const SizedBox(height: 12),
        if (crm.isEmpty)
          _EmptySection(message: 'No invoices for this client yet.')
        else
          ...crm.map((e) => _CrmRow(entry: e)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: AppTextStyles.dataMd
                .copyWith(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: AppTextStyles.bodySm
                .copyWith(color: AppColors.onSurfaceVariant, fontSize: 11)),
      ]),
    );
  }
}

class _TaskCostRow extends StatelessWidget {
  const _TaskCostRow({required this.task});
  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        const Icon(Icons.task_alt_outlined, size: 16, color: AppColors.gold),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: AppTextStyles.labelMd,
              overflow: TextOverflow.ellipsis),
          Text(task.statusLabel,
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant, fontSize: 10)),
        ])),
        Text('EGP ${task.cost!.toStringAsFixed(2)}',
            style: AppTextStyles.dataMd.copyWith(color: AppColors.gold)),
      ]),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value, this.positive});
  final String label, value;
  final bool? positive;

  @override
  Widget build(BuildContext context) {
    final color = positive == null
        ? Colors.white70
        : positive! ? const Color(0xFF81C784) : AppColors.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: AppTextStyles.dataMd.copyWith(color: color, fontSize: 15)),
      Text(label,
          style: AppTextStyles.bodySm.copyWith(color: Colors.white38, fontSize: 10)),
    ]);
  }
}

class _CrmRow extends StatelessWidget {
  const _CrmRow({required this.entry});
  final CrmEntry entry;

  Color _statusColor() {
    switch (entry.status) {
      case 'paid':     return const Color(0xFF81C784);
      case 'overdue':  return AppColors.error;
      case 'partial':  return AppColors.gold;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.title, style: AppTextStyles.labelMd),
          if (entry.invoiceNumber != null)
            Text('INV ${entry.invoiceNumber}',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('EGP ${entry.amount.toStringAsFixed(0)}', style: AppTextStyles.dataMd),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(entry.statusLabel,
                style: AppTextStyles.bodySm.copyWith(color: _statusColor(), fontSize: 10)),
          ),
        ]),
      ]),
    );
  }
}

// ── Tasks tab ──────────────────────────────────────────────────────────────────
class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.tasks});
  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return _EmptySection(message: 'No tasks assigned to this client.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _TaskRow(task: tasks[i]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final TaskModel task;

  Color _priorityColor() {
    switch (task.priority) {
      case 'critical': return AppColors.error;
      case 'high':     return AppColors.statusHigh;
      case 'medium':   return AppColors.gold;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: _priorityColor(), width: 3),
        ),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: AppTextStyles.labelMd),
          const SizedBox(height: 4),
          Row(children: [
            _Chip(label: task.statusLabel, color: AppColors.primary),
            if (task.dueDate != null) ...[
              const SizedBox(width: 8),
              _Chip(label: task.dueDateDisplay, color: AppColors.outlineVariant),
            ],
          ]),
        ])),
        if (task.cost != null && task.cost! > 0)
          Text('EGP ${task.cost!.toStringAsFixed(0)}',
              style: AppTextStyles.dataMd.copyWith(color: AppColors.gold)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: AppTextStyles.bodySm.copyWith(color: color, fontSize: 10)),
    );
  }
}

// ── Meetings tab ───────────────────────────────────────────────────────────────
class _MeetingsTab extends StatelessWidget {
  const _MeetingsTab({required this.events});
  final List<CalEventData> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _EmptySection(message: 'No meetings scheduled for this client.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _MeetingRow(event: events[i]),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.event});
  final CalEventData event;

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${AppTime.hm(d)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(event.title, style: AppTextStyles.labelMd)),
          if (event.cost != null && event.cost! > 0)
            Text('EGP ${event.cost!.toStringAsFixed(0)}',
                style: AppTextStyles.dataMd.copyWith(color: AppColors.gold)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.access_time_outlined, size: 13, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(_fmt(event.start), style: AppTextStyles.dataSm),
        ]),
        if (event.attendeeNames.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: event.attendeeNames.map((n) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(n,
                  style: AppTextStyles.bodySm
                      .copyWith(fontSize: 10, color: AppColors.primary)),
            )).toList(),
          ),
        ],
      ]),
    );
  }
}

// ── Shared empty state ─────────────────────────────────────────────────────────
class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(message,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
