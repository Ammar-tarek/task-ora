// lib/features/analytics/advanced_analytics_screen.dart
// Real task analytics. Admin: all or a specific department. Manager: own team.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/team_model.dart';
import '../../core/repositories/analytics_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';

class AdvancedAnalyticsScreen extends StatefulWidget {
  const AdvancedAnalyticsScreen({super.key});
  @override
  State<AdvancedAnalyticsScreen> createState() => _AdvancedAnalyticsScreenState();
}

class _AdvancedAnalyticsScreenState extends State<AdvancedAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool _loading = true;
  bool _isAdmin = false;
  String? _myTeamId;
  List<TeamModel> _teams = [];
  String _dept = 'all'; // admin filter: 'all' or a department name
  List<TaskStat> _rows = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<AuthNotifier>().profile;
      _isAdmin   = p?.isAdmin == true;
      _myTeamId  = p?.teamId;
      if (_isAdmin) {
        try { _teams = await TeamRepository.fetchAllAdmin(); } catch (_) {}
      }
      _load();
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  List<String> get _departments {
    final set = <String>{};
    for (final t in _teams) {
      final d = t.department?.trim();
      if (d != null && d.isNotEmpty) set.add(d);
    }
    return set.toList()..sort();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<String>? teamIds;
    if (_isAdmin) {
      if (_dept != 'all') {
        teamIds = _teams
            .where((t) => (t.department ?? '') == _dept)
            .map((t) => t.id)
            .toList();
      }
    } else {
      teamIds = _myTeamId != null ? [_myTeamId!] : <String>[];
    }
    final rows = await AnalyticsRepository.fetchTaskStats(teamIds: teamIds);
    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Advanced Analytics'),
        actions: [
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButton<String>(
                value: _dept,
                underline: const SizedBox(),
                icon: const Icon(Icons.filter_list, color: AppColors.gold),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All departments')),
                  ..._departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _dept = v);
                  _load();
                },
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: AppTextStyles.labelMd,
          unselectedLabelStyle: AppTextStyles.bodySm,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Team')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _rows.isEmpty
              ? _empty()
              : TabBarView(controller: _tabs, children: [
                  _overview(),
                  _team(),
                ]),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart, size: 48, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(_isAdmin && _dept != 'all'
                  ? 'No tasks in $_dept'
                  : 'No tasks to analyze yet',
              style: AppTextStyles.labelMd),
        ]),
      );

  // ── Overview ────────────────────────────────────────────────────────────────
  Widget _overview() {
    final total     = _rows.length;
    final completed = _rows.where((r) => r.isCompleted).length;
    final overdue   = _rows.where((r) => r.isOverdue).length;
    final inProg    = _rows.where((r) => r.status == 'in_progress').length;
    final rate      = total == 0 ? 0 : (completed / total * 100).round();

    final byStatus = <String, int>{};
    for (final r in _rows) { byStatus[r.status] = (byStatus[r.status] ?? 0) + 1; }

    final high = _rows.where((r) => r.priority == 'high' || r.priority == 'critical').length;
    final med  = _rows.where((r) => r.priority == 'medium').length;
    final low  = _rows.where((r) => r.priority == 'low').length;

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6,
            children: [
              TStatCard(title: 'TOTAL TASKS', value: '$total', icon: Icons.list_alt_outlined),
              TStatCard(title: 'COMPLETION RATE', value: '$rate%', icon: Icons.pie_chart_outline),
              TStatCard(title: 'IN PROGRESS', value: '$inProg', icon: Icons.trending_up),
              TStatCard(title: 'OVERDUE', value: '$overdue', icon: Icons.warning_outlined, accent: overdue > 0),
            ],
          ),
          const SizedBox(height: 24),
          Text('STATUS BREAKDOWN', style: AppTextStyles.labelCaps),
          const SizedBox(height: 12),
          ...byStatus.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 110,
                  child: Text(_statusLabel(e.key), style: AppTextStyles.bodyMd)),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : e.value / total, minHeight: 18,
                  backgroundColor: AppColors.outlineVariant,
                  color: _statusColor(e.key),
                ),
              )),
              const SizedBox(width: 8),
              Text('${e.value}', style: AppTextStyles.dataSm),
            ]),
          )),
          const SizedBox(height: 24),
          Text('PRIORITY DISTRIBUTION', style: AppTextStyles.labelCaps),
          const SizedBox(height: 12),
          Container(
            height: 32,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              if (high > 0) Expanded(flex: high, child: Container(color: AppColors.statusHigh,
                child: Center(child: Text('High $high', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))))),
              if (med > 0) Expanded(flex: med, child: Container(color: AppColors.gold,
                child: Center(child: Text('Med $med', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600))))),
              if (low > 0) Expanded(flex: low, child: Container(color: AppColors.statusDone,
                child: Center(child: Text('Low $low', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))))),
              if (high + med + low == 0) Expanded(child: Container(color: AppColors.outlineVariant)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Team workload ───────────────────────────────────────────────────────────
  Widget _team() {
    final byUser = <String, int>{};
    for (final r in _rows) {
      for (final a in r.assignees) { byUser[a] = (byUser[a] ?? 0) + 1; }
    }
    final entries = byUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.isEmpty ? 1 : entries.first.value;

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WORKLOAD DISTRIBUTION', style: AppTextStyles.labelCaps),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text('No assigned tasks.',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant))
          else
            ...entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(children: [
                TAvatar(name: e.key, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key, style: AppTextStyles.labelMd),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: e.value / maxVal, minHeight: 5,
                      backgroundColor: AppColors.outlineVariant, color: AppColors.gold,
                    ),
                  ),
                ])),
                const SizedBox(width: 12),
                Text('${e.value} tasks', style: AppTextStyles.dataSm),
              ]),
            )),
        ]),
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'not_started':     return 'To Do';
      case 'in_progress':     return 'In Progress';
      case 'employee_done':   return 'Employee Done';
      case 'client_approved': return 'Client Approved';
      case 'client_rejected': return 'Client Rejected';
      case 'completed':       return 'Completed';
      case 'on_hold':         return 'On Hold';
      default:                return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':       return AppColors.statusDone;
      case 'in_progress':     return AppColors.statusInProgress;
      case 'client_rejected': return AppColors.error;
      case 'on_hold':         return AppColors.outline;
      default:                return AppColors.statusTodo;
    }
  }
}
