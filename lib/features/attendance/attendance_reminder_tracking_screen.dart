// lib/features/attendance/attendance_reminder_tracking_screen.dart
//
// Manager/admin view of the daily attendance-reminder outcome:
// who was reminded, when, whether they checked in, and the exact time.
// Team scoping is enforced server-side by the get_reminder_tracking RPC;
// admins additionally get the global TeamFilterChip to narrow by team.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/repositories/reminder_tracking_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';
import '../../core/widgets/team_filter_chip.dart';

enum _Filter { all, sent, after, absent, before }

class AttendanceReminderTrackingScreen extends StatefulWidget {
  const AttendanceReminderTrackingScreen({super.key});
  @override
  State<AttendanceReminderTrackingScreen> createState() =>
      _AttendanceReminderTrackingScreenState();
}

class _AttendanceReminderTrackingScreenState
    extends State<AttendanceReminderTrackingScreen> {
  List<ReminderTrackingRow> _rows = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  DateTime _date = AppTime.now();
  TeamFilterNotifier? _teamFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _teamFilter = context.read<TeamFilterNotifier>()
        ..loadTeams()
        ..addListener(_onTeamChange);
      _load();
    });
    // Reminders and check-ins both change the picture live.
    RealtimeService.instance.listen(
      const ['attendance', 'attendance_reminders'],
      _onRealtime,
    );
  }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onRealtime() {
    if (mounted) _load();
  }

  void _onTeamChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    // Admins may narrow by team; managers are scoped server-side regardless.
    final teamId = profile?.isAdmin == true
        ? context.read<TeamFilterNotifier>().selectedTeamId
        : null;
    final data = await ReminderTrackingRepository.fetch(
      date: _date,
      teamId: teamId,
    );
    if (mounted) {
      setState(() {
        _rows = data;
        _loading = false;
      });
    }
  }

  Future<void> _sendManual() async {
    final profile = context.read<AuthNotifier>().profile;
    final isAdmin = profile?.isAdmin == true;
    final teamId =
        isAdmin ? context.read<TeamFilterNotifier>().selectedTeamId : null;
    final scopeLabel = isAdmin
        ? (context.read<TeamFilterNotifier>().selectedTeam?.name ?? 'all teams')
        : 'your team';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send reminder now?'),
        content: Text(
          'This sends a push notification to everyone in $scopeLabel who has '
          'not checked in yet today.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (confirmed != true) return;

    final n = await ReminderTrackingRepository.sendManual(teamId: teamId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(n > 0
            ? 'Reminder sent to $n employee${n == 1 ? '' : 's'}.'
            : 'No one to remind — everyone in scope has checked in.'),
      ),
    );
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024, 1, 1),
      lastDate: AppTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  // ── Derived counts ─────────────────────────────────────────────────────────
  int get _total => _rows.length;
  int get _sent => _rows.where((r) => r.reminderSent).length;
  int get _after =>
      _rows.where((r) => r.status == ReminderStatus.checkedInAfter).length;
  int get _absent =>
      _rows.where((r) => r.status == ReminderStatus.stillAbsent).length;

  List<ReminderTrackingRow> get _visible {
    switch (_filter) {
      case _Filter.all:
        return _rows;
      case _Filter.sent:
        return _rows.where((r) => r.reminderSent).toList();
      case _Filter.after:
        return _rows
            .where((r) => r.status == ReminderStatus.checkedInAfter)
            .toList();
      case _Filter.absent:
        return _rows
            .where((r) => r.status == ReminderStatus.stillAbsent)
            .toList();
      case _Filter.before:
        // "Checked in before the reminder" = anyone present without a
        // reminder-after outcome: those reminded then found already-in, AND
        // those who checked in early so no reminder was ever sent.
        return _rows
            .where((r) =>
                r.status == ReminderStatus.checkedInBefore ||
                r.status == ReminderStatus.checkedInNoReminder)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthNotifier, bool>(
      (a) => a.profile?.isAdmin == true,
    );
    final canManage = context.select<AuthNotifier, bool>(
      (a) => a.profile?.isAdminOrManager == true,
    );
    final isToday = _date.toIso8601String().substring(0, 10) ==
        AppTime.now().toIso8601String().substring(0, 10);
    final dateLabel =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reminder Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      // Manual "remind now" — only for managers/admins, only on today.
      floatingActionButton: (canManage && isToday)
          ? FloatingActionButton.extended(
              onPressed: _sendManual,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.notifications_active, color: AppColors.gold),
              label: const Text('Remind now',
                  style: TextStyle(color: AppColors.gold)),
            )
          : null,
      body: Column(
        children: [
          if (isAdmin) const TeamFilterChip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 16, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(dateLabel, style: AppTextStyles.labelMd),
              ],
            ),
          ),
          _summaryCards(),
          _filterBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Text('No employees',
                            style: AppTextStyles.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _Row(
                            row: _visible[i],
                            showTeam: isAdmin,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'TOTAL',
                    value: '$_total',
                    color: AppColors.onSurface)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    label: 'REMINDERS SENT',
                    value: '$_sent',
                    color: AppColors.statusInProgress)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    label: 'CHECKED IN AFTER',
                    value: '$_after',
                    color: AppColors.statusDone)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    label: 'STILL ABSENT',
                    value: '$_absent',
                    color: AppColors.error)),
          ],
        ),
      );

  Widget _filterBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            _chip('All', _Filter.all),
            _chip('Reminder sent', _Filter.sent),
            _chip('Checked in after', _Filter.after),
            _chip('Still absent', _Filter.absent),
            _chip('Checked in before', _Filter.before),
          ],
        ),
      );

  Widget _chip(String label, _Filter f) {
    final selected = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = f),
        labelStyle: AppTextStyles.labelMd.copyWith(
          color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
        ),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surfaceContainerLowest,
        side: BorderSide(color: AppColors.outlineVariant),
      ),
    );
  }
}

// ── Status presentation ──────────────────────────────────────────────────────
class _StatusView {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusView(this.label, this.color, this.icon);

  factory _StatusView.of(ReminderStatus s) {
    switch (s) {
      case ReminderStatus.checkedInAfter:
        return _StatusView(
            'Checked in after reminder', AppColors.statusDone, Icons.check_circle);
      case ReminderStatus.checkedInBefore:
        return _StatusView('Already checked in', AppColors.statusInProgress,
            Icons.info_outline);
      case ReminderStatus.stillAbsent:
        return _StatusView('Still absent', AppColors.error, Icons.cancel);
      case ReminderStatus.checkedInNoReminder:
        return _StatusView('Checked in (no reminder)', AppColors.statusInProgress,
            Icons.check_circle_outline);
      case ReminderStatus.noReminder:
        return _StatusView('No reminder', AppColors.onSurfaceVariant,
            Icons.remove_circle_outline);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.showTeam});
  final ReminderTrackingRow row;
  final bool showTeam;

  String _time(DateTime? utc) =>
      utc == null ? '—' : AppTime.hm(AppTime.cairo(utc));

  @override
  Widget build(BuildContext context) {
    final sv = _StatusView.of(row.status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.fullName,
                        style: AppTextStyles.bodyMd
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (showTeam)
                      Text(row.teamName ?? 'No team',
                          style: AppTextStyles.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sv.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(sv.icon, size: 14, color: sv.color),
                    const SizedBox(width: 4),
                    Text(sv.label,
                        style: AppTextStyles.labelCaps.copyWith(color: sv.color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _kv(
                  'Reminder',
                  row.reminderSent
                      ? 'Sent ${_time(row.reminderSentAt)}'
                      : 'Not sent',
                ),
              ),
              Expanded(child: _kv('Check-in', _time(row.checkIn))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(v, style: AppTextStyles.dataMd),
        ],
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 24)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelCaps
                    .copyWith(fontSize: 9, color: AppColors.onSurfaceVariant)),
          ],
        ),
      );
}
