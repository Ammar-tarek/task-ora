// lib/features/team/employee_performance_screen.dart
// Read-only employee performance hub: overview counts, task history, monthly
// attendance, and recorded deductions. All reads are RLS-scoped to the viewer.

import 'package:flutter/material.dart';
import '../../core/repositories/attendance_repository.dart';
import '../../core/repositories/penalty_repository.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/theme/app_theme.dart';
import 'team_performance_repository.dart';

class EmployeePerformanceScreen extends StatefulWidget {
  final TeamMember member;
  const EmployeePerformanceScreen({super.key, required this.member});

  @override
  State<EmployeePerformanceScreen> createState() => _EmployeePerformanceScreenState();
}

class _EmployeePerformanceScreenState extends State<EmployeePerformanceScreen> {
  bool _loading = true;
  List<EmployeeTaskRow> _rows = [];
  EmployeeTaskSummary _summary = const EmployeeTaskSummary();
  List<AttendanceRecord> _attendance = [];
  List<PenaltyItem> _penalties = []; // all; filtered to month in getters
  List<AssignmentRejection> _rejections = []; // durable history (audit log)

  late int _year;
  late int _month;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final id = widget.member.id;
    final tasks = await TaskRepository.fetchTasksAssignedTo(id);
    final penalties = await PenaltyRepository.fetchForEmployee(id);
    final rejections = await TeamPerformanceRepository.fetchAssignmentRejections(id);
    final rows = TeamPerformanceRepository.rowsFor(tasks, id);
    final att = await AttendanceRepository.fetchForEmployeeMonthly(
      employeeId: id, year: _year, month: _month,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _summary = TeamPerformanceRepository.summarize(rows);
      _penalties = penalties;
      _attendance = att;
      _rejections = rejections;
      _loading = false;
    });
  }

  /// Only attendance depends on the month; reload it on month change.
  Future<void> _loadMonth() async {
    final att = await AttendanceRepository.fetchForEmployeeMonthly(
      employeeId: widget.member.id, year: _year, month: _month,
    );
    if (mounted) setState(() => _attendance = att);
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) { _month = 12; _year--; } else { _month--; }
    });
    _loadMonth();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year == now.year && _month == now.month) return;
    setState(() {
      if (_month == 12) { _month = 1; _year++; } else { _month++; }
    });
    _loadMonth();
  }

  String get _monthPrefix =>
      '$_year-${_month.toString().padLeft(2, '0')}';

  List<PenaltyItem> get _monthPenalties =>
      _penalties.where((p) => p.date.startsWith(_monthPrefix)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.member.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _overview(),
                  const SizedBox(height: 20),
                  _sectionTitle('TASK HISTORY'),
                  const SizedBox(height: 8),
                  _taskHistory(),
                  const SizedBox(height: 20),
                  _sectionTitle('REJECTED ASSIGNMENTS'),
                  const SizedBox(height: 8),
                  _rejectionsSection(),
                  const SizedBox(height: 20),
                  _monthNav(),
                  const SizedBox(height: 12),
                  _sectionTitle('MONTHLY ATTENDANCE'),
                  const SizedBox(height: 8),
                  _attendanceSection(),
                  const SizedBox(height: 20),
                  _sectionTitle('DEDUCTIONS'),
                  const SizedBox(height: 8),
                  _deductionsSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t) =>
      Align(alignment: Alignment.centerLeft, child: Text(t, style: AppTextStyles.labelCaps));

  // ── A. Overview ─────────────────────────────────────────────────────────────
  Widget _overview() {
    final s = _summary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.member.name, style: AppTextStyles.headlineSm),
          Text(widget.member.role,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat('Assigned', s.assigned, AppColors.gold),
              _stat('In Progress', s.inProgress, AppColors.statusInProgress),
              _stat('Awaiting Review', s.awaitingReview, AppColors.statusMedium),
              _stat('Completed', s.completed, AppColors.statusDone),
              _stat('Changes Requested', s.changesRequested, AppColors.statusHigh),
              _stat('Awaiting Acceptance', s.awaitingAcceptance, AppColors.statusInProgress),
              // Rejections come from the durable audit log (the assignee row is
              // removed on reject), so this reflects full history, not live rows.
              _stat('Assignment Rejected', _rejections.length, AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Container(
      width: 104,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 22)),
          Text(label, style: AppTextStyles.bodySm.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  // ── B. Task history (grouped, single bucket each) ───────────────────────────
  Widget _taskHistory() {
    if (_rows.isEmpty) return _empty('No tasks assigned');
    const groups = [
      ('awaiting_acceptance', 'Awaiting Acceptance'),
      ('awaiting_review', 'Awaiting Review'),
      ('in_progress', 'In Progress'),
      ('changes_requested', 'Changes Requested'),
      ('completed', 'Approved / Completed'),
      ('other', 'Other'),
    ];
    final widgets = <Widget>[];
    for (final g in groups) {
      final rows = _rows.where((r) => r.bucket == g.$1).toList();
      if (rows.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text('${g.$2} (${rows.length})',
            style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
      ));
      widgets.addAll(rows.map(_taskTile));
    }
    return Column(children: widgets);
  }

  Widget _taskTile(EmployeeTaskRow r) {
    final t = r.task;
    final rejected = r.response == 'rejected';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.title, style: AppTextStyles.labelMd)),
              TStatusChip(label: t.statusLabel, color: AppColors.secondary),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Due ${t.dueDateDisplay}',
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              const Spacer(),
              // Assignment response (distinct from the review status chip above).
              if (r.response != null && r.response != 'accepted')
                Text(
                  rejected ? 'Assignment rejected' : 'Awaiting acceptance',
                  style: AppTextStyles.bodySm.copyWith(
                    color: rejected ? AppColors.error : AppColors.statusInProgress,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          if (rejected && (r.responseReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Reason: ${r.responseReason}',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.error, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  // ── B2. Rejected assignments (durable history from audit log) ───────────────
  Widget _rejectionsSection() {
    if (_rejections.isEmpty) return _empty('No rejected assignments');
    return Column(
      children: _rejections.map((r) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.taskTitle, style: AppTextStyles.labelMd)),
                    Text(
                      r.at.length >= 16 ? r.at.substring(0, 16).replaceFirst('T', ' ') : r.at,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
                if (r.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Reason: ${r.reason}',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
                ],
              ],
            ),
          )).toList(),
    );
  }

  // ── C. Monthly attendance ───────────────────────────────────────────────────
  Widget _monthNav() {
    final now = DateTime.now();
    final atCurrent = _year == now.year && _month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.gold),
          onPressed: _prevMonth,
        ),
        Text('${_monthNames[_month - 1]} $_year', style: AppTextStyles.labelMd),
        IconButton(
          icon: Icon(Icons.chevron_right,
              color: atCurrent ? AppColors.outlineVariant : AppColors.gold),
          onPressed: _nextMonth,
        ),
      ],
    );
  }

  Widget _attendanceSection() {
    if (_attendance.isEmpty) return _empty('No attendance records this month');
    int present = 0, late = 0, absent = 0, half = 0;
    for (final a in _attendance) {
      switch (a.status) {
        case 'late': late++; break;
        case 'absent': absent++; break;
        case 'half_day': half++; break;
        default: present++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _stat('Present', present, AppColors.statusDone),
          _stat('Late', late, AppColors.statusHigh),
          _stat('Half Day', half, AppColors.statusMedium),
          _stat('Absent', absent, AppColors.error),
        ]),
        const SizedBox(height: 10),
        ..._attendance.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(a.date, style: AppTextStyles.bodySm)),
                  Text(a.statusLabel,
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                  if (a.totalHours != null) ...[
                    const SizedBox(width: 10),
                    Text('${a.totalHours!.toStringAsFixed(1)}h', style: AppTextStyles.dataSm),
                  ],
                ],
              ),
            )),
      ],
    );
  }

  // ── D. Deductions / penalties (read-only) ───────────────────────────────────
  Widget _deductionsSection() {
    final list = _monthPenalties;
    if (list.isEmpty) return _empty('No deductions this month');
    return Column(
      children: list.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.penaltyType, style: AppTextStyles.labelMd)),
                    Text('${p.amount.toStringAsFixed(2)} EGP',
                        style: AppTextStyles.dataMd.copyWith(color: AppColors.statusHigh)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Text(p.date, style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Text('· ${p.status}', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
                if (p.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.reason, style: AppTextStyles.bodySm),
                ],
              ],
            ),
          )).toList(),
    );
  }

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(msg, style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        ),
      );
}
