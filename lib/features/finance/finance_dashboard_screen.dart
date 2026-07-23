// lib/features/finance/finance_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/client_model.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/expense_repository.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/team_filter_chip.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  List<ClientModel> _clients = [];
  FinanceSummary _summary = const FinanceSummary();
  List<ExpenseItem> _expenses = [];
  List<Map<String, dynamic>> _monthly = [];
  bool _loading = true;

  TeamFilterNotifier? _teamFilter;
  String? _filterClientType; // department name → client_type filter
  String? _filterTeamId; // for expense scoping

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final profile = context.read<AuthNotifier>().profile;
      if (profile?.isAdmin == true) {
        _teamFilter = context.read<TeamFilterNotifier>()
          ..loadTeams()
          ..addListener(_onTeamChange);
      } else if (profile?.isManager == true && profile?.teamId != null) {
        // Manager: scope to their department automatically
        final team = await TeamRepository.fetchById(profile!.teamId!);
        if (mounted) {
          _filterClientType = team?.department?.toLowerCase();
          _filterTeamId = team?.id;
        }
      }
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onTeamChange() {
    final selected = _teamFilter?.selectedTeam;
    _filterClientType = selected?.department?.toLowerCase();
    _filterTeamId = selected?.id;
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ClientRepository.fetchClients(clientType: _filterClientType),
        FinanceRepository.fetchSummary(
          teamId: _filterTeamId,
          clientType: _filterClientType,
        ),
        ExpenseRepository.fetchAll(limit: 5, teamId: _filterTeamId),
        FinanceRepository.fetchMonthlyBreakdown(teamId: _filterTeamId),
      ]);
      if (mounted) {
        setState(() {
          _clients = results[0] as List<ClientModel>;
          _summary = results[1] as FinanceSummary;
          _expenses = results[2] as List<ExpenseItem>;
          _monthly = results[3] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final isAdmin = profile?.isAdmin ?? false;
    final title = (profile?.isManager == true && _filterClientType != null)
        ? 'Finance — ${_filterClientType![0].toUpperCase()}${_filterClientType!.substring(1)}'
        : 'Finance';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => context.push('/finance/analytics'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const TeamFilterChip(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Hero revenue card ────────────────────────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL REVENUE',
                                  style: AppTextStyles.labelCaps.copyWith(
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _fmtAmount(_summary.grossRevenue),
                                  style: AppTextStyles.dataLg.copyWith(
                                    color: AppColors.gold,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _MiniStat(
                                      label: 'Task Services',
                                      value: _fmtAmount(_summary.taskRevenue),
                                    ),
                                    const SizedBox(width: 20),
                                    _MiniStat(
                                      label: 'Meetings',
                                      value: _fmtAmount(
                                        _summary.meetingRevenue,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    _MiniStat(
                                      label: 'Invoiced',
                                      value: _fmtAmount(_summary.totalInvoiced),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 24,
                                ),
                                Row(
                                  children: [
                                    _MiniStat(
                                      label: 'Expenses',
                                      value: _fmtAmount(_summary.totalExpenses),
                                      isNegative: true,
                                    ),
                                    const SizedBox(width: 24),
                                    _MiniStat(
                                      label: 'Net Profit',
                                      value: _fmtAmount(_summary.netProfit),
                                      isPositive: true,
                                    ),
                                    const SizedBox(width: 24),
                                    _MiniStat(
                                      label: 'Outstanding',
                                      value: _fmtAmount(_summary.outstanding),
                                      isNegative: _summary.outstanding > 0,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Quick stat cards ─────────────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: TStatCard(
                                  title: 'PENDING INVOICES',
                                  value: '${_summary.pendingInvoices}',
                                  icon: Icons.receipt_outlined,
                                  sub: 'Not yet paid',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TStatCard(
                                  title: 'OVERDUE',
                                  value: '${_summary.overdueCount}',
                                  icon: Icons.warning_amber_outlined,
                                  sub: 'Needs attention',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Revenue trend chart ──────────────────────────────────────
                          TSectionHeader(
                            title: 'Revenue Trend (6 months)',
                            action: 'Full Analytics',
                            onAction: () => context.push('/finance/analytics'),
                          ),
                          const SizedBox(height: 12),
                          _monthly.isEmpty
                              ? _EmptyCard(message: 'No revenue data yet.')
                              : _BarChart(data: _monthly),
                          const SizedBox(height: 24),

                          // ── Paid vs Outstanding ──────────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'Paid',
                                  value: _fmtAmount(_summary.totalPaid),
                                  color: const Color(0xFF81C784),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: 'Outstanding',
                                  value: _fmtAmount(_summary.outstanding),
                                  color: _summary.outstanding > 0
                                      ? AppColors.error
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Recent expenses ──────────────────────────────────────────
                          TSectionHeader(
                            title: 'Recent Expenses',
                            action: 'All Expenses',
                            onAction: () => context.push('/expenses'),
                          ),
                          const SizedBox(height: 12),
                          if (_expenses.isEmpty)
                            _EmptyCard(message: 'No expenses recorded yet.')
                          else
                            ..._expenses.map((e) => _ExpenseRow(expense: e)),
                          const SizedBox(height: 24),

                          // ── Clients ──────────────────────────────────────────────────
                          TSectionHeader(
                            title: 'Clients',
                            action: isAdmin ? 'Manage Clients' : 'View Clients',
                            onAction: () => context.push('/clients'),
                          ),
                          const SizedBox(height: 12),
                          if (_clients.isEmpty)
                            _EmptyCard(
                              message: isAdmin
                                  ? 'No clients yet. Go to Clients to create one.'
                                  : 'No clients yet.',
                            )
                          else
                            ..._clients
                                .take(5)
                                .map((c) => _ClientFinanceRow(client: c)),
                          if (_clients.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton(
                                onPressed: () => context.push('/clients'),
                                child: Text(
                                  'View all ${_clients.length} clients',
                                  style: AppTextStyles.labelMd.copyWith(
                                    color: AppColors.goldDark,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Amount formatter ───────────────────────────────────────────────────────────
String _fmtAmount(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

// ── Bar chart using real monthly data ─────────────────────────────────────────
class _BarChart extends StatelessWidget {
  const _BarChart({required this.data});
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    final values = data.map((d) => (d['value'] as double)).toList();
    final maxVal = values.fold(0.0, (a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1.0 : maxVal;

    return Container(
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final val = d['value'] as double;
          final ratio = val / safeMax;
          final isLast = d == data.last;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (val > 0)
                    Text(
                      _fmtAmount(val),
                      style: AppTextStyles.bodySm.copyWith(
                        fontSize: 9,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    height: (ratio * 90).clamp(6.0, 90.0),
                    decoration: BoxDecoration(
                      color: isLast
                          ? AppColors.gold
                          : AppColors.primary.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d['month'] as String,
                    style: AppTextStyles.bodySm.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.isPositive = false,
    this.isNegative = false,
  });
  final String label, value;
  final bool isPositive, isNegative;

  @override
  Widget build(BuildContext context) {
    final color = isPositive
        ? const Color(0xFF81C784)
        : isNegative
        ? AppColors.error
        : Colors.white70;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTextStyles.dataMd.copyWith(color: color, fontSize: 15),
        ),
        Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            color: Colors.white38,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.dataMd.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final ExpenseItem expense;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description.isNotEmpty
                      ? expense.description
                      : 'Expense',
                  style: AppTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${expense.categoryName} · ${expense.date}',
                  style: AppTextStyles.bodySm,
                ),
              ],
            ),
          ),
          Text(
            '${_fmtAmount(expense.amount)} EGP',
            style: AppTextStyles.dataMd.copyWith(color: AppColors.statusHigh),
          ),
        ],
      ),
    );
  }
}

class _ClientFinanceRow extends StatelessWidget {
  const _ClientFinanceRow({required this.client});
  final ClientModel client;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/clients/${client.id}/finance'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                client.initials,
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.gold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.companyName, style: AppTextStyles.labelMd),
                  if (client.contactPerson.isNotEmpty)
                    Text(
                      client.contactPerson,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.outlineVariant),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    );
  }
}
