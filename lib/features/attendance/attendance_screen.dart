// lib/features/attendance/attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/attendance_repository.dart';
import '../../core/theme/app_theme.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _records = [];
  AttendanceRecord? _myRecord;
  bool _loading = true;
  String _selectedDate = DateTime.now().toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;

    if (profile?.isAdminOrManager == true) {
      final data = await AttendanceRepository.fetchByDate(_selectedDate);
      if (mounted) setState(() { _records = data; _loading = false; });
    } else {
      // Employee: show own record for selected date + today's check-in status
      final results = await Future.wait([
        AttendanceRepository.fetchForEmployee(profile?.id ?? ''),
        AttendanceRepository.fetchTodayForEmployee(profile?.id ?? ''),
      ]);
      if (mounted) {
        setState(() {
          _records  = results[0] as List<AttendanceRecord>;
          _myRecord = results[1] as AttendanceRecord?;
          _loading  = false;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final profile   = context.watch<AuthNotifier>().profile;
    final isManager = profile?.isAdminOrManager == true;
    final dateDisp  = DateFormat('d MMMM y')
        .format(DateTime.tryParse(_selectedDate) ?? DateTime.now());

    final present = _records.where((r) => r.status == 'present').length;
    final absent  = _records.where((r) => r.status == 'absent').length;
    final late    = _records.where((r) => r.status == 'late').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          if (isManager)
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _pickDate,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Employee self-service card ──────────────────────────────
                  if (!isManager) ...[
                    _SelfServiceCard(
                      record:   _myRecord,
                      onCheckIn: () async {
                        await AttendanceRepository.checkIn(profile!.id);
                        _load();
                      },
                      onCheckOut: () async {
                        await AttendanceRepository.checkOut(profile!.id);
                        _load();
                      },
                    ),
                    const SizedBox(height: 24),
                    Text('MY ATTENDANCE HISTORY', style: AppTextStyles.labelCaps),
                    const SizedBox(height: 12),
                    if (_records.isEmpty)
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 32),
                          const Icon(Icons.event_busy_outlined,
                            size: 64, color: AppColors.outlineVariant),
                          const SizedBox(height: 12),
                          Text('No records yet', style: AppTextStyles.labelMd),
                        ]),
                      )
                    else
                      ..._records.map((r) => _AttendanceRow(
                        record:    r,
                        isManager: false,
                        onEdit:    null,
                      )),
                  ],

                  // ── Admin / manager view ────────────────────────────────────
                  if (isManager) ...[
                    Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(dateDisp,
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.onSurfaceVariant)),
                      const Spacer(),
                      TextButton(
                        onPressed: _pickDate,
                        child: Text('Change date',
                          style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    Row(children: [
                      Expanded(child: _StatCard(
                        label: 'PRESENT', value: '$present',
                        color: AppColors.statusDone)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(
                        label: 'ABSENT',  value: '$absent',
                        color: AppColors.statusHigh)),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(
                        label: 'LATE',    value: '$late',
                        color: AppColors.gold)),
                    ]),
                    const SizedBox(height: 24),

                    Text('TEAM ATTENDANCE', style: AppTextStyles.labelCaps),
                    const SizedBox(height: 12),

                    if (_records.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.event_busy_outlined,
                              size: 64, color: AppColors.outlineVariant),
                            const SizedBox(height: 12),
                            Text('No records for this date', style: AppTextStyles.labelMd),
                          ]),
                        ),
                      )
                    else
                      ..._records.map((r) => _AttendanceRow(
                        record:    r,
                        isManager: true,
                        onEdit: () => _showOverrideDialog(r),
                      )),
                  ],
                ]),
              ),
            ),
    );
  }

  Future<void> _showOverrideDialog(AttendanceRecord record) async {
    await showDialog(
      context: context,
      builder: (_) => _OverrideDialog(
        record:  record,
        onSaved: _load,
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
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) { return '—'; }
  }

  @override
  Widget build(BuildContext context) {
    final checked = record?.isCheckedIn == true;
    final done    = record?.isCheckedOut == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.today_outlined, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Text("Today's Status", style: AppTextStyles.labelMd.copyWith(color: Colors.white)),
          const Spacer(),
          if (record?.isOverridden == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Manually adjusted',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.gold, fontSize: 10)),
            ),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _TimeChip(
            label: 'Check-in',
            time: record?.checkInTime != null ? _fmt(record!.checkInTime!) : '—',
            icon: Icons.login_outlined,
            active: checked,
          ),
          const Icon(Icons.arrow_forward, color: Colors.white54, size: 20),
          _TimeChip(
            label: 'Check-out',
            time: record?.checkOutTime != null ? _fmt(record!.checkOutTime!) : '—',
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
        ]),
        const SizedBox(height: 16),
        Row(children: [
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
        ]),
      ]),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.time, required this.icon, required this.active});
  final String label, time;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: active ? AppColors.gold : Colors.white30, size: 20),
    const SizedBox(height: 4),
    Text(time, style: AppTextStyles.labelMd.copyWith(
      color: active ? Colors.white : Colors.white38, fontSize: 13)),
    Text(label, style: AppTextStyles.bodySm.copyWith(color: Colors.white38, fontSize: 10)),
  ]);
}

// ── Attendance row ──────────────────────────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.record, required this.isManager, this.onEdit});
  final AttendanceRecord record;
  final bool isManager;
  final VoidCallback? onEdit;

  Color get _statusColor {
    switch (record.status) {
      case 'present':  return AppColors.statusDone;
      case 'absent':   return AppColors.statusHigh;
      case 'late':     return AppColors.gold;
      case 'half_day': return AppColors.statusMedium;
      default:         return AppColors.onSurfaceVariant;
    }
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return '—'; }
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
          color: record.isOverridden
              ? AppColors.gold.withValues(alpha: 0.4)
              : AppColors.outlineVariant,
        ),
      ),
      child: Row(children: [
        TAvatar(name: record.employeeName, size: 40),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(record.employeeName, style: AppTextStyles.labelMd),
            if (record.isOverridden) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 12, color: AppColors.gold),
            ],
          ]),
          if (record.checkInTime != null || record.checkOutTime != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (record.checkInTime  != null) 'In: ${_fmt(record.checkInTime!)}',
                if (record.checkOutTime != null) 'Out: ${_fmt(record.checkOutTime!)}',
                if (record.totalHours   != null) '${record.totalHours!.toStringAsFixed(1)}h',
              ].join('  '),
              style: AppTextStyles.bodySm,
            ),
          ],
          if (isManager && record.isOverridden && record.overrideReason != null) ...[
            const SizedBox(height: 2),
            Text('Note: ${record.overrideReason}',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.gold, fontSize: 11)),
          ],
          // Show date in history view for employees
          if (!isManager) ...[
            const SizedBox(height: 2),
            Text(record.date,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ])),
        TStatusChip(label: record.statusLabel, color: _statusColor),
        if (isManager && onEdit != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.gold),
            tooltip: 'Override attendance',
            onPressed: onEdit,
          ),
        ],
      ]),
    );
  }
}

// ── Override Dialog ─────────────────────────────────────────────────────────

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.record, required this.onSaved});
  final AttendanceRecord record;
  final VoidCallback onSaved;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _reasonCtrl = TextEditingController();
  TimeOfDay _inTime  = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _outTime = const TimeOfDay(hour: 17, minute: 0);
  String _status = 'present';
  bool _saving = false;

  static const _statuses = ['present', 'late', 'half_day', 'absent'];

  @override
  void initState() {
    super.initState();
    // Pre-fill from existing record
    if (widget.record.checkInTime != null) {
      final dt = DateTime.tryParse(widget.record.checkInTime!);
      if (dt != null) _inTime = TimeOfDay.fromDateTime(dt.toLocal());
    }
    if (widget.record.checkOutTime != null) {
      final dt = DateTime.tryParse(widget.record.checkOutTime!);
      if (dt != null) _outTime = TimeOfDay.fromDateTime(dt.toLocal());
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
    return '${date}T${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:00';
  }

  Future<void> _save() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for the override')),
      );
      return;
    }
    setState(() => _saving = true);
    await AttendanceRepository.overrideAttendance(
      employeeId:   widget.record.employeeId,
      date:         widget.record.date,
      checkInTime:  _buildDateTime(widget.record.date, _inTime),
      checkOutTime: _buildDateTime(widget.record.date, _outTime),
      reason:       _reasonCtrl.text.trim(),
      status:       _status,
    );
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  Future<void> _pickTime(bool isIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? _inTime : _outTime,
    );
    if (picked != null) setState(() => isIn ? _inTime = picked : _outTime = picked);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Override: ${widget.record.employeeName}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.record.date,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 16),

            // Status
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _statuses.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ')),
              )).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'present'),
            ),
            const SizedBox(height: 12),

            // Check-in time
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Check-in: ${_fmtTime(_inTime)}', style: AppTextStyles.bodyMd),
              trailing: const Icon(Icons.access_time_outlined, color: AppColors.gold),
              onTap: () => _pickTime(true),
            ),

            // Check-out time
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Check-out: ${_fmtTime(_outTime)}', style: AppTextStyles.bodyMd),
              trailing: const Icon(Icons.access_time_outlined, color: AppColors.gold),
              onTap: () => _pickTime(false),
            ),
            const SizedBox(height: 8),

            // Reason
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for override *',
                hintText: 'e.g. WiFi was down, forgot to check out...',
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Override'),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});
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
    child: Column(children: [
      Text(value, style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 28)),
      const SizedBox(height: 4),
      Text(label, style: AppTextStyles.labelCaps),
    ]),
  );
}
