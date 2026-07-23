// lib/features/attendance/attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/providers/team_privileges_notifier.dart';
import '../../core/repositories/attendance_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';
import '../../core/widgets/team_filter_chip.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _records = [];
  AttendanceRecord? _myRecord;
  bool _loading = true;
  String _selectedDate = AppTime.now().toIso8601String().substring(0, 10);
  TeamFilterNotifier? _teamFilter;

  // ── Monthly summary mode (admin/manager) ──────────────────────────────────
  bool _summaryMode = false;
  int _sumYear = AppTime.now().year;
  int _sumMonth = AppTime.now().month;
  String? _sumEmployeeId; // null = all in scope
  List<EmpAttendanceSummary> _summaries = [];
  bool _summaryLoading = false;

  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    final profile = context.read<AuthNotifier>().profile;
    final teamId = profile?.isAdmin == true
        ? context.read<TeamFilterNotifier>().selectedTeamId
        : profile?.teamId;
    // Fetch the whole scope; the employee dropdown filters the display.
    final data = await AttendanceRepository.fetchMonthlySummary(
      year: _sumYear,
      month: _sumMonth,
      teamId: teamId,
    );
    if (mounted)
      setState(() {
        _summaries = data;
        _summaryLoading = false;
      });
  }

  void _shiftMonth(int delta) {
    var m = _sumMonth + delta, y = _sumYear;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    setState(() {
      _sumMonth = m;
      _sumYear = y;
    });
    _loadSummary();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _teamFilter = context.read<TeamFilterNotifier>()
        ..loadTeams()
        ..addListener(_onTeamChange);
      _load();
    });
    // Live refresh when any attendance row changes.
    RealtimeService.instance.listen(const ['attendance'], _onRealtime);
  }

  void _onRealtime() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onTeamChange() {
    if (!mounted) return;
    _sumEmployeeId = null; // department changed → reset employee filter
    if (_summaryMode) _loadSummary();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    // Also reload privileges so grants/restrictions take effect immediately.
    await context.read<TeamPrivilegesNotifier>().reload();
    final canManage =
        profile?.isAdmin == true ||
        context.read<TeamPrivilegesNotifier>().canManageAttendance;

    if (canManage) {
      // Admin: respect the team switcher. Manager/granted: scoped to their team.
      String? teamId;
      if (profile!.isAdmin) {
        teamId = context.read<TeamFilterNotifier>().selectedTeamId;
      } else {
        teamId = profile.teamId;
      }
      final data = await AttendanceRepository.fetchByDate(
        _selectedDate,
        teamId: teamId,
      );
      // Managers are tracked too — load their own today record for the
      // self-service check-in/out card.
      AttendanceRecord? mine;
      if (profile.isManager) {
        mine = await AttendanceRepository.fetchTodayForEmployee(profile.id);
      }
      if (mounted)
        setState(() {
          _records = data;
          _myRecord = mine;
          _loading = false;
        });
    } else {
      final results = await Future.wait([
        AttendanceRepository.fetchForEmployee(profile?.id ?? ''),
        AttendanceRepository.fetchTodayForEmployee(profile?.id ?? ''),
      ]);
      if (mounted) {
        setState(() {
          _records = results[0] as List<AttendanceRecord>;
          _myRecord = results[1] as AttendanceRecord?;
          _loading = false;
        });
      }
    }
  }

  void _showEmployeeDetails(EmpAttendanceSummary summary) {
    showDialog(
      context: context,
      builder: (_) => _EmployeeMonthlyAttendanceDialog(
        employeeId: summary.employeeId,
        employeeName: summary.name,
        year: _sumYear,
        month: _sumMonth,
        onRefreshParent: _loadSummary,
      ),
    );
  }

  Widget _buildSummary() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final shown = _sumEmployeeId == null
        ? _summaries
        : _summaries.where((s) => s.employeeId == _sumEmployeeId).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftMonth(-1),
              ),
              Expanded(
                child: Text(
                  '${months[_sumMonth - 1]} $_sumYear',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shiftMonth(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String?>(
            value: _sumEmployeeId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Employee',
              prefixIcon: Icon(Icons.person_search_outlined),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All employees'),
              ),
              ..._summaries.map(
                (s) => DropdownMenuItem<String?>(
                  value: s.employeeId,
                  child: Text(s.name),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _sumEmployeeId = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _summaryLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                )
              : shown.isEmpty
              ? Center(
                  child: Text(
                    'No employees in this scope',
                    style: AppTextStyles.labelMd,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SummaryCard(
                    s: shown[i],
                    onTap: () => _showEmployeeDetails(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_selectedDate) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked.toIso8601String().substring(0, 10));
      _load();
    }
  }

  Future<void> _approveRecord(AttendanceRecord record) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    await AttendanceRepository.approveAttendance(
      attendanceId: record.id,
      approvedBy: profile.id,
    );
    _load();
  }

  Future<void> _doCheckIn() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    final err = await AttendanceRepository.checkIn(profile.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
          content: Text('Check-in failed: $err'),
        ),
      );
    }
    _load();
  }

  Future<void> _doCheckOut() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;

    // Require a daily report before checking out.
    final report = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DailyReportDialog(),
    );
    if (report == null) return; // cancelled → stay checked in

    final err = await AttendanceRepository.checkOut(
      profile.id,
      dailyReport: report,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
          content: Text('Check-out failed: $err'),
        ),
      );
    }
    _load();
  }

  Future<void> _viewReport(AttendanceRecord r) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              color: AppColors.gold,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.employeeName} · ${r.date}',
                style: AppTextStyles.labelMd,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            r.hasReport ? r.dailyReport! : 'No report submitted.',
            style: AppTextStyles.bodyMd,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualEntryDialog(AttendanceRecord? existing) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    await showDialog(
      context: context,
      builder: (_) => _ManualAttendanceDialog(
        employeeId: profile.id,
        existing: existing,
        onSaved: _load,
      ),
    );
  }

  Future<void> _showOverrideDialog(AttendanceRecord record) async {
    await showDialog(
      context: context,
      builder: (_) => _OverrideDialog(record: record, onSaved: _load),
    );
  }

  Future<void> _showAdminAddAttendanceDialog() async {
    await showDialog(
      context: context,
      builder: (_) => _AdminAddAttendanceDialog(
        initialDate: _selectedDate,
        onSaved: () {
          if (_summaryMode) _loadSummary();
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final privs = context.watch<TeamPrivilegesNotifier>();
    // "Manager view" = anyone who can manage attendance: admin, a manager with
    // the privilege, or an employee explicitly granted it.
    final isManager = profile?.isAdmin == true || privs.canManageAttendance;
    final canManageAttendance = isManager;
    final dateDisp = DateFormat(
      'd MMMM y',
    ).format(DateTime.tryParse(_selectedDate) ?? DateTime.now());

    final present = _records.where((r) => r.status == 'present').length;
    final absent = _records.where((r) => r.status == 'absent').length;
    final late = _records.where((r) => r.status == 'late').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          // Admin/manager: switch between daily records and monthly summary.
          if (isManager)
            IconButton(
              icon: Icon(
                _summaryMode
                    ? Icons.event_note_outlined
                    : Icons.bar_chart_outlined,
              ),
              tooltip: _summaryMode ? 'Daily records' : 'Monthly summary',
              onPressed: () {
                setState(() => _summaryMode = !_summaryMode);
                if (_summaryMode) _loadSummary();
              },
            ),
          if (isManager && !_summaryMode)
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _pickDate,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _summaryMode ? _loadSummary : _load,
          ),
        ],
      ),
      // FAB for employee self-service or admin/manager manual entry
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isManager
            ? _showAdminAddAttendanceDialog
            : () => _showManualEntryDialog(null),
        backgroundColor: AppColors.primary,
        icon: Icon(
          isManager ? Icons.person_add_alt_1_outlined : Icons.add,
          color: AppColors.gold,
        ),
        label: Text(
          isManager ? 'Add Attendance' : 'Log Attendance',
          style: const TextStyle(color: AppColors.gold),
        ),
      ),
      body: Column(
        children: [
          const TeamFilterChip(),
          if (isManager && _summaryMode)
            Expanded(child: _buildSummary())
          else
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : RefreshIndicator(
                      color: AppColors.gold,
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Employee self-service card ──────────────────────────────
                            if (!isManager) ...[
                              _SelfServiceCard(
                                record: _myRecord,
                                onCheckIn: _doCheckIn,
                                onCheckOut: _doCheckOut,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'MY ATTENDANCE HISTORY',
                                style: AppTextStyles.labelCaps,
                              ),
                              const SizedBox(height: 12),
                              if (_records.isEmpty)
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 32),
                                      Icon(
                                        Icons.event_busy_outlined,
                                        size: 64,
                                        color: AppColors.outlineVariant,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No records yet',
                                        style: AppTextStyles.labelMd,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Use the button below to log attendance',
                                        style: AppTextStyles.bodySm.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._records.map(
                                  (r) => _AttendanceRow(
                                    record: r,
                                    isManager: false,
                                    onEdit: r.isApproved
                                        ? null
                                        : () => _showManualEntryDialog(r),
                                    onApprove: null,
                                    onReport: r.hasReport
                                        ? () => _viewReport(r)
                                        : null,
                                  ),
                                ),
                              // Bottom padding so FAB doesn't overlap last item
                              const SizedBox(height: 80),
                            ],

                            // ── Manager's own check-in/out card (managers are tracked) ──
                            if (isManager && profile?.isManager == true) ...[
                              _SelfServiceCard(
                                record: _myRecord,
                                onCheckIn: _doCheckIn,
                                onCheckOut: _doCheckOut,
                              ),
                              const SizedBox(height: 24),
                            ],

                            // ── Admin / manager view ────────────────────────────────────
                            if (isManager) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateDisp,
                                    style: AppTextStyles.labelMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _pickDate,
                                    child: Text(
                                      'Change date',
                                      style: AppTextStyles.labelMd.copyWith(
                                        color: AppColors.gold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _showAdminAddAttendanceDialog,
                                    icon: const Icon(
                                      Icons.add,
                                      size: 16,
                                      color: AppColors.gold,
                                    ),
                                    label: const Text(
                                      'Add Attendance',
                                      style: TextStyle(color: AppColors.gold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      textStyle: AppTextStyles.labelMd,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      label: 'PRESENT',
                                      value: '$present',
                                      color: AppColors.statusDone,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      label: 'ABSENT',
                                      value: '$absent',
                                      color: AppColors.statusHigh,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      label: 'LATE',
                                      value: '$late',
                                      color: AppColors.gold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              Text(
                                'TEAM ATTENDANCE',
                                style: AppTextStyles.labelCaps,
                              ),
                              const SizedBox(height: 12),

                              if (_records.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.event_busy_outlined,
                                          size: 64,
                                          color: AppColors.outlineVariant,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No records for this date',
                                          style: AppTextStyles.labelMd,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ..._records.map(
                                  (r) => _AttendanceRow(
                                    record: r,
                                    isManager: true,
                                    onEdit: canManageAttendance
                                        ? () => _showOverrideDialog(r)
                                        : null,
                                    // A manager cannot approve their OWN attendance (admin can).
                                    onApprove:
                                        (!canManageAttendance ||
                                            r.isApproved ||
                                            (profile?.isManager == true &&
                                                r.employeeId == profile?.id))
                                        ? null
                                        : () => _approveRecord(r),
                                    onReport: () => _viewReport(r),
                                  ),
                                ),
                            ],
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

// ── Self-service card (employee) ──────────────────────────────────────────

class _SelfServiceCard extends StatelessWidget {
  const _SelfServiceCard({
    required this.record,
    required this.onCheckIn,
    required this.onCheckOut,
  });
  final AttendanceRecord? record;
  final Future<void> Function() onCheckIn;
  final Future<void> Function() onCheckOut;

  String _fmt(String iso) {
    try {
      final dt = AppTime.cairo(DateTime.parse(iso));
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final checked = record?.isCheckedIn == true;
    final done = record?.isCheckedOut == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.today_outlined, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                "Today's Status",
                style: AppTextStyles.labelMd.copyWith(color: Colors.white),
              ),
              const Spacer(),
              if (record?.isApproved == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusDone.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Approved',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.statusDone,
                      fontSize: 10,
                    ),
                  ),
                )
              else if (record?.isOverridden == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Manually adjusted',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.gold,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TimeChip(
                label: 'Check-in',
                time: record?.checkInTime != null
                    ? _fmt(record!.checkInTime!)
                    : '—',
                icon: Icons.login_outlined,
                active: checked,
              ),
              const Icon(Icons.arrow_forward, color: Colors.white54, size: 20),
              _TimeChip(
                label: 'Check-out',
                time: record?.checkOutTime != null
                    ? _fmt(record!.checkOutTime!)
                    : '—',
                icon: Icons.logout_outlined,
                active: done,
              ),
              if (record?.totalHours != null)
                _TimeChip(
                  label: 'Hours',
                  time: '${record!.totalHours!.toStringAsFixed(1)}h',
                  icon: Icons.access_time_outlined,
                  active: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login_outlined, size: 18),
                  label: const Text('Check In'),
                  onPressed: (checked && !done) ? null : onCheckIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusDone,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout_outlined, size: 18),
                  label: const Text('Check Out'),
                  onPressed: (checked && !done) ? onCheckOut : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.time,
    required this.icon,
    required this.active,
  });
  final String label, time;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: active ? AppColors.gold : Colors.white30, size: 20),
      const SizedBox(height: 4),
      Text(
        time,
        style: AppTextStyles.labelMd.copyWith(
          color: active ? Colors.white : Colors.white38,
          fontSize: 13,
        ),
      ),
      Text(
        label,
        style: AppTextStyles.bodySm.copyWith(
          color: Colors.white38,
          fontSize: 10,
        ),
      ),
    ],
  );
}

// ── Attendance row ──────────────────────────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({
    required this.record,
    required this.isManager,
    this.onEdit,
    this.onApprove,
    this.onReport,
  });
  final AttendanceRecord record;
  final bool isManager;
  final VoidCallback? onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReport;

  Color get _statusColor {
    switch (record.status) {
      case 'present':
        return AppColors.statusDone;
      case 'absent':
        return AppColors.statusHigh;
      case 'late':
        return AppColors.gold;
      case 'half_day':
        return AppColors.statusMedium;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  String _fmt(String iso) {
    try {
      final dt = AppTime.cairo(DateTime.parse(iso));
      return AppTime.hm(dt);
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: record.isApproved
              ? AppColors.statusDone.withValues(alpha: 0.4)
              : record.isOverridden
              ? AppColors.gold.withValues(alpha: 0.4)
              : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TAvatar(name: record.employeeName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(record.employeeName, style: AppTextStyles.labelMd),
                        if (record.isApproved) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_outlined,
                            size: 12,
                            color: AppColors.statusDone,
                          ),
                        ] else if (record.isManual) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.edit_note_outlined,
                            size: 12,
                            color: AppColors.gold,
                          ),
                        ] else if (record.isOverridden) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.edit_outlined,
                            size: 12,
                            color: AppColors.gold,
                          ),
                        ],
                      ],
                    ),
                    if (record.checkInTime != null ||
                        record.checkOutTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (record.checkInTime != null)
                            'In: ${_fmt(record.checkInTime!)}',
                          if (record.checkOutTime != null)
                            'Out: ${_fmt(record.checkOutTime!)}',
                          if (record.totalHours != null)
                            '${record.totalHours!.toStringAsFixed(1)}h',
                        ].join('  '),
                        style: AppTextStyles.bodySm,
                      ),
                    ],
                    if (isManager &&
                        record.isOverridden &&
                        record.overrideReason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Note: ${record.overrideReason}',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.gold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (!isManager &&
                        record.isManual &&
                        record.manualNote != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Note: ${record.manualNote}',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (!isManager) ...[
                      const SizedBox(height: 2),
                      Text(
                        record.date,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Status chip
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TStatusChip(label: record.statusLabel, color: _statusColor),
                  if (record.isApproved) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusDone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.statusDone.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'Approved',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.statusDone,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Compact, non-overlapping action icons (wrap when tight).
              if (_actions.isNotEmpty) ...[
                const SizedBox(width: 4),
                Wrap(spacing: 0, runSpacing: 0, children: _actions),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> get _actions {
    Widget btn(IconData icon, Color color, String tip, VoidCallback? on) =>
        IconButton(
          icon: Icon(icon, size: 18, color: color),
          tooltip: tip,
          onPressed: on,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
    return [
      if (record.hasReport && onReport != null)
        btn(
          Icons.description_outlined,
          AppColors.gold,
          'View daily report',
          onReport,
        ),
      if (onEdit != null)
        btn(
          Icons.edit_outlined,
          AppColors.gold,
          isManager ? 'Override attendance' : 'Edit attendance',
          onEdit,
        ),
      if (onApprove != null)
        btn(
          Icons.check_circle_outline,
          AppColors.statusDone,
          'Approve attendance',
          onApprove,
        ),
    ];
  }
}

// ── Manual Attendance Dialog (employee self-service) ────────────────────────

class _ManualAttendanceDialog extends StatefulWidget {
  const _ManualAttendanceDialog({
    required this.employeeId,
    this.existing,
    required this.onSaved,
  });
  final String employeeId;
  final AttendanceRecord? existing;
  final VoidCallback onSaved;

  @override
  State<_ManualAttendanceDialog> createState() =>
      _ManualAttendanceDialogState();
}

class _ManualAttendanceDialogState extends State<_ManualAttendanceDialog> {
  final _noteCtrl = TextEditingController();
  TimeOfDay _inTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _outTime = const TimeOfDay(hour: 17, minute: 0);
  DateTime _date = DateTime.now().subtract(const Duration(days: 1));
  String _status = 'present';
  bool _saving = false;
  String? _error;

  static const _statuses = ['present', 'late', 'half_day'];

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _date = DateTime.tryParse(r.date) ?? _date;
      if (r.checkInTime != null) {
        final dt = DateTime.tryParse(r.checkInTime!);
        if (dt != null) _inTime = TimeOfDay.fromDateTime(AppTime.cairo(dt));
      }
      if (r.checkOutTime != null) {
        final dt = DateTime.tryParse(r.checkOutTime!);
        if (dt != null) _outTime = TimeOfDay.fromDateTime(AppTime.cairo(dt));
      }
      _status = r.status == 'absent' ? 'present' : r.status;
      _noteCtrl.text = r.manualNote ?? '';
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _buildDateTime(DateTime date, TimeOfDay t) {
    // User picks Egypt wall time — store as UTC so display converts back.
    return AppTime.fromCairoToUtc(
      date.year,
      date.month,
      date.day,
      t.hour,
      t.minute,
    ).toIso8601String();
  }

  bool _endsAfterStart() {
    final inMins = _inTime.hour * 60 + _inTime.minute;
    final outMins = _outTime.hour * 60 + _outTime.minute;
    return outMins > inMins;
  }

  Future<void> _save() async {
    // Check-out must be after check-in.
    if (!_endsAfterStart()) {
      setState(() => _error = 'Check-out time must be after check-in time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await AttendanceRepository.manualAddAttendance(
      employeeId: widget.employeeId,
      date:
          '${_date.year.toString().padLeft(4, '0')}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}',
      checkInTime: _buildDateTime(_date, _inTime),
      checkOutTime: _buildDateTime(_date, _outTime),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      status: _status,
    );
    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        widget.onSaved();
      } else {
        setState(() {
          _saving = false;
          _error =
              'Could not save attendance. Please check the times and try again.';
        });
      }
    }
  }

  Future<void> _pickTime(bool isIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? _inTime : _outTime,
    );
    if (picked != null)
      setState(() => isIn ? _inTime = picked : _outTime = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _fmtTime(TimeOfDay t) => AppTime.hm2(t.hour, t.minute);

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Attendance' : 'Log Manual Attendance'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Date: ${_fmtDate(_date)}',
                  style: AppTextStyles.bodyMd,
                ),
                trailing: const Icon(
                  Icons.calendar_today_outlined,
                  color: AppColors.gold,
                ),
                onTap: isEdit ? null : _pickDate,
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Status
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statuses
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s[0].toUpperCase() +
                              s.substring(1).replaceAll('_', ' '),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? 'present'),
              ),
              const SizedBox(height: 12),

              // Check-in time
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Check-in: ${_fmtTime(_inTime)}',
                  style: AppTextStyles.bodyMd,
                ),
                trailing: const Icon(
                  Icons.access_time_outlined,
                  color: AppColors.gold,
                ),
                onTap: () => _pickTime(true),
              ),

              // Check-out time
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Check-out: ${_fmtTime(_outTime)}',
                  style: AppTextStyles.bodyMd,
                ),
                trailing: const Icon(
                  Icons.access_time_outlined,
                  color: AppColors.gold,
                ),
                onTap: () => _pickTime(false),
              ),
              const SizedBox(height: 8),

              // Note
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Reason for manual entry…',
                ),
              ),

              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This record will be pending until a manager approves it.',
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.gold),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEdit ? 'Update' : 'Submit'),
        ),
      ],
    );
  }
}

// ── Override Dialog (admin / manager) ──────────────────────────────────────

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.record, required this.onSaved});
  final AttendanceRecord record;
  final VoidCallback onSaved;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _reasonCtrl = TextEditingController();
  TimeOfDay _inTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _outTime = const TimeOfDay(hour: 17, minute: 0);
  String _status = 'present';
  bool _saving = false;
  String? _error;

  static const _statuses = ['present', 'late', 'half_day', 'absent'];

  @override
  void initState() {
    super.initState();
    if (widget.record.checkInTime != null) {
      final dt = DateTime.tryParse(widget.record.checkInTime!);
      if (dt != null) _inTime = TimeOfDay.fromDateTime(AppTime.cairo(dt));
    }
    if (widget.record.checkOutTime != null) {
      final dt = DateTime.tryParse(widget.record.checkOutTime!);
      if (dt != null) _outTime = TimeOfDay.fromDateTime(AppTime.cairo(dt));
    }
    _status = widget.record.status;
    _reasonCtrl.text = widget.record.overrideReason ?? '';
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _buildDateTime(String date, TimeOfDay t) {
    // User picks Egypt wall time — store as UTC so display converts back.
    final p = date.split('-').map(int.parse).toList();
    return AppTime.fromCairoToUtc(
      p[0],
      p[1],
      p[2],
      t.hour,
      t.minute,
    ).toIso8601String();
  }

  bool get _isAbsent => _status == 'absent';

  bool _endsAfterStart() {
    final inMins = _inTime.hour * 60 + _inTime.minute;
    final outMins = _outTime.hour * 60 + _outTime.minute;
    return outMins > inMins;
  }

  Future<void> _save() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a reason for the override.');
      return;
    }
    // Time validation only applies when there are times (not for absent).
    if (!_isAbsent && !_endsAfterStart()) {
      setState(() => _error = 'Check-out time must be after check-in time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await AttendanceRepository.overrideAttendance(
      employeeId: widget.record.employeeId,
      date: widget.record.date,
      checkInTime: _buildDateTime(widget.record.date, _inTime),
      checkOutTime: _buildDateTime(widget.record.date, _outTime),
      reason: _reasonCtrl.text.trim(),
      status: _status,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      widget.onSaved();
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  Future<void> _pickTime(bool isIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? _inTime : _outTime,
    );
    if (picked != null)
      setState(() => isIn ? _inTime = picked : _outTime = picked);
  }

  String _fmtTime(TimeOfDay t) => AppTime.hm2(t.hour, t.minute);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Override: ${widget.record.employeeName}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.record.date,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statuses
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s[0].toUpperCase() +
                              s.substring(1).replaceAll('_', ' '),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _status = v ?? 'present';
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),

              // Absent days have no check-in/out times.
              if (!_isAbsent) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Check-in: ${_fmtTime(_inTime)}',
                    style: AppTextStyles.bodyMd,
                  ),
                  trailing: const Icon(
                    Icons.access_time_outlined,
                    color: AppColors.gold,
                  ),
                  onTap: () => _pickTime(true),
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Check-out: ${_fmtTime(_outTime)}',
                    style: AppTextStyles.bodyMd,
                  ),
                  trailing: const Icon(
                    Icons.access_time_outlined,
                    color: AppColors.gold,
                  ),
                  onTap: () => _pickTime(false),
                ),
              ] else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statusHigh.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Marked absent — no check-in/out times recorded.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.statusHigh,
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for override *',
                  hintText: 'e.g. WiFi was down, forgot to check out…',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Override'),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 28),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.labelCaps),
      ],
    ),
  );
}

// ── Daily report dialog (required on check-out) ─────────────────────────────
class _DailyReportDialog extends StatefulWidget {
  const _DailyReportDialog();
  @override
  State<_DailyReportDialog> createState() => _DailyReportDialogState();
}

class _DailyReportDialogState extends State<_DailyReportDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      setState(() => _error = 'Please write your daily report.');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      title: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            color: AppColors.gold,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text('Daily Report', style: AppTextStyles.headlineSm),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Before checking out, write what you did today.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 5,
              autofocus: true,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'Tasks completed, meetings, progress…',
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Submit & Check Out'),
        ),
      ],
    );
  }
}

// ── Monthly summary card (per employee) ─────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.s, required this.onTap});
  final EmpAttendanceSummary s;
  final VoidCallback onTap;

  Widget _pill(String label, int value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      '$label $value',
      style: AppTextStyles.bodySm.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            TAvatar(name: s.name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: AppTextStyles.labelMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill('Attended', s.attended, AppColors.statusDone),
                      _pill('Absent', s.absent, AppColors.statusHigh),
                      _pill('Late', s.late, AppColors.gold),
                      if (s.halfDay > 0)
                        _pill('Half', s.halfDay, AppColors.statusMedium),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Monthly attendance detail dialog ────────────────────────────────────────
class _EmployeeMonthlyAttendanceDialog extends StatefulWidget {
  const _EmployeeMonthlyAttendanceDialog({
    required this.employeeId,
    required this.employeeName,
    required this.year,
    required this.month,
    required this.onRefreshParent,
  });

  final String employeeId;
  final String employeeName;
  final int year;
  final int month;
  final VoidCallback onRefreshParent;

  @override
  State<_EmployeeMonthlyAttendanceDialog> createState() =>
      __EmployeeMonthlyAttendanceDialogState();
}

class __EmployeeMonthlyAttendanceDialogState
    extends State<_EmployeeMonthlyAttendanceDialog> {
  List<AttendanceRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AttendanceRepository.fetchForEmployeeMonthly(
      employeeId: widget.employeeId,
      year: widget.year,
      month: widget.month,
    );
    if (mounted) {
      setState(() {
        _records = data;
        _loading = false;
      });
    }
  }

  Future<void> _approveRecord(AttendanceRecord record) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    await AttendanceRepository.approveAttendance(
      attendanceId: record.id,
      approvedBy: profile.id,
    );
    widget.onRefreshParent();
    _load();
  }

  Future<void> _showOverrideDialog(AttendanceRecord record) async {
    await showDialog(
      context: context,
      builder: (_) => _OverrideDialog(
        record: record,
        onSaved: () {
          widget.onRefreshParent();
          _load();
        },
      ),
    );
  }

  Future<void> _viewReport(AttendanceRecord r) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              color: AppColors.gold,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.employeeName} · ${r.date}',
                style: AppTextStyles.labelMd,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            r.hasReport ? r.dailyReport! : 'No report submitted.',
            style: AppTextStyles.bodyMd,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final privs = context.watch<TeamPrivilegesNotifier>();
    final isManager = profile?.isAdmin == true || privs.canManageAttendance;
    final canManageAttendance = isManager;

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return AlertDialog(
      backgroundColor: AppColors.background,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.employeeName, style: AppTextStyles.headlineSm),
                const SizedBox(height: 2),
                Text(
                  '${months[widget.month - 1]} ${widget.year}',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 450,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : _records.isEmpty
            ? Center(
                child: Text(
                  'No attendance records found.',
                  style: AppTextStyles.labelMd,
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount: _records.length,
                itemBuilder: (context, i) {
                  final r = _records[i];
                  return _AttendanceRow(
                    record: r,
                    isManager: isManager,
                    onEdit: canManageAttendance
                        ? () => _showOverrideDialog(r)
                        : null,
                    onApprove:
                        (!canManageAttendance ||
                            r.isApproved ||
                            (profile?.isManager == true &&
                                r.employeeId == profile?.id))
                        ? null
                        : () => _approveRecord(r),
                    onReport: () => _viewReport(r),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AdminAddAttendanceDialog extends StatefulWidget {
  const _AdminAddAttendanceDialog({
    required this.initialDate,
    required this.onSaved,
  });

  final String initialDate;
  final VoidCallback onSaved;

  @override
  State<_AdminAddAttendanceDialog> createState() =>
      _AdminAddAttendanceDialogState();
}

class _AdminAddAttendanceDialogState extends State<_AdminAddAttendanceDialog> {
  final _reasonCtrl = TextEditingController();
  List<Map<String, String>> _employees = [];
  bool _loadingEmployees = true;
  String? _selectedEmployeeId;
  late String _selectedDate;
  TimeOfDay _inTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _outTime = const TimeOfDay(hour: 17, minute: 0);
  String _status = 'present';
  bool _saving = false;
  String? _error;

  static const _statuses = ['present', 'late', 'half_day', 'absent'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final data = await SupabaseService.adminClient
          .from('profiles')
          .select('id, full_name')
          .neq('role', 'client')
          .eq('status', 'active')
          .order('full_name');
      final list = (data as List)
          .map(
            (m) => {
              'id': m['id'] as String,
              'name': m['full_name'] as String? ?? 'Unknown',
            },
          )
          .toList();
      if (mounted) {
        setState(() {
          _employees = list;
          if (list.isNotEmpty) _selectedEmployeeId = list.first['id'];
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _buildDateTime(String date, TimeOfDay t) {
    final p = date.split('-').map(int.parse).toList();
    return AppTime.fromCairoToUtc(
      p[0],
      p[1],
      p[2],
      t.hour,
      t.minute,
    ).toIso8601String();
  }

  bool get _isAbsent => _status == 'absent';

  bool _endsAfterStart() {
    final inMins = _inTime.hour * 60 + _inTime.minute;
    final outMins = _outTime.hour * 60 + _outTime.minute;
    return outMins > inMins;
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _pickTime(bool isIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? _inTime : _outTime,
    );
    if (picked != null)
      setState(() => isIn ? _inTime = picked : _outTime = picked);
  }

  String _fmtTime(TimeOfDay t) => AppTime.hm2(t.hour, t.minute);

  Future<void> _save() async {
    if (_selectedEmployeeId == null) {
      setState(() => _error = 'Please select an employee.');
      return;
    }
    if (!_isAbsent && !_endsAfterStart()) {
      setState(() => _error = 'Check-out time must be after check-in time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final note = _reasonCtrl.text.trim().isNotEmpty
        ? _reasonCtrl.text.trim()
        : 'Manual admin attendance entry';

    final err = await AttendanceRepository.overrideAttendance(
      employeeId: _selectedEmployeeId!,
      date: _selectedDate,
      checkInTime: _buildDateTime(_selectedDate, _inTime),
      checkOutTime: _buildDateTime(_selectedDate, _outTime),
      reason: note,
      status: _status,
    );

    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      widget.onSaved();
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person_add_alt_1_outlined, color: AppColors.gold),
          SizedBox(width: 8),
          Text('Add Employee Attendance'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _loadingEmployees
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    DropdownButtonFormField<String>(
                      value: _selectedEmployeeId,
                      decoration: const InputDecoration(
                        labelText: 'Employee *',
                      ),
                      items: _employees
                          .map(
                            (e) => DropdownMenuItem(
                              value: e['id'],
                              child: Text(e['name'] ?? 'Unknown'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedEmployeeId = v),
                    ),
                    const SizedBox(height: 12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Date: $_selectedDate',
                        style: AppTextStyles.bodyMd,
                      ),
                      trailing: const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.gold,
                      ),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 8),

                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: _statuses
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s[0].toUpperCase() +
                                    s.substring(1).replaceAll('_', ' '),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _status = v ?? 'present';
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 12),

                    if (!_isAbsent) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Check-in: ${_fmtTime(_inTime)}',
                          style: AppTextStyles.bodyMd,
                        ),
                        trailing: const Icon(
                          Icons.access_time_outlined,
                          color: AppColors.gold,
                        ),
                        onTap: () => _pickTime(true),
                      ),

                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Check-out: ${_fmtTime(_outTime)}',
                          style: AppTextStyles.bodyMd,
                        ),
                        trailing: const Icon(
                          Icons.access_time_outlined,
                          color: AppColors.gold,
                        ),
                        onTap: () => _pickTime(false),
                      ),
                      const SizedBox(height: 8),
                    ],

                    TextField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note / Reason',
                        hintText:
                            'e.g. Manual admin entry for official mission',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColors.gold,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Save Attendance',
                  style: TextStyle(color: AppColors.gold),
                ),
        ),
      ],
    );
  }
}
