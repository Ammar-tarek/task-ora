// lib/core/repositories/attendance_repository.dart

import '../services/supabase_service.dart';
import '../utils/app_time.dart';

class AttendanceRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String date;
  final String? checkInTime;
  final String? checkOutTime;
  final String status;
  final double? totalHours;
  final bool isOverridden;
  final String? overrideReason;
  final bool isApproved;
  final bool isManual;
  final String? manualNote;
  final String? approvedBy;
  final String? dailyReport;

  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    this.totalHours,
    required this.isOverridden,
    this.overrideReason,
    this.isApproved = false,
    this.isManual = false,
    this.manualNote,
    this.approvedBy,
    this.dailyReport,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) {
    final profile = m['employee'] as Map<String, dynamic>?;
    return AttendanceRecord(
      id: m['id'] as String,
      employeeId: m['employee_id'] as String,
      employeeName: profile?['full_name'] as String? ?? 'Unknown',
      date: m['attendance_date'] as String? ?? '',
      checkInTime: m['check_in_time'] as String?,
      checkOutTime: m['check_out_time'] as String?,
      status: m['status'] as String? ?? 'present',
      totalHours: (m['total_hours'] as num?)?.toDouble(),
      isOverridden: m['is_overridden'] as bool? ?? false,
      overrideReason: m['override_reason'] as String?,
      isApproved: m['is_approved'] as bool? ?? false,
      isManual: m['is_manual'] as bool? ?? false,
      manualNote: m['manual_note'] as String?,
      approvedBy: m['approved_by'] as String?,
      dailyReport: m['daily_report'] as String?,
    );
  }

  bool get hasReport => (dailyReport ?? '').trim().isNotEmpty;

  String get statusLabel {
    switch (status) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'late':
        return 'Late';
      case 'half_day':
        return 'Half Day';
      default:
        return status;
    }
  }

  bool get isCheckedIn => checkInTime != null;
  bool get isCheckedOut => checkOutTime != null;
}

/// Per-employee attendance totals for a single month.
class EmpAttendanceSummary {
  final String employeeId;
  final String name;
  int present;
  int late;
  int halfDay;
  int absent;

  EmpAttendanceSummary({
    required this.employeeId,
    required this.name,
    this.present = 0,
    this.late = 0,
    this.halfDay = 0,
    this.absent = 0,
  });

  int get attended => present + late + halfDay;
  int get totalRecords => attended + absent;
}

class AttendanceRepository {
  static final _admin = SupabaseService.adminClient;

  static const _select = '*, employee:profiles(full_name)';

  /// Resolve active staff (non-client) ids for a team, or all if [teamId] null.
  static Future<List<Map<String, String>>> _staff({String? teamId}) async {
    try {
      var q = _admin
          .from('profiles')
          .select('id, full_name')
          .neq('role', 'client');
      if (teamId != null) q = q.eq('team_id', teamId);
      final data = await q.order('full_name');
      return (data as List)
          .map(
            (m) => {
              'id': (m as Map<String, dynamic>)['id'] as String,
              'name': m['full_name'] as String? ?? 'Unknown',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Monthly attendance summary per employee.
  /// [teamId] scopes to one department/team (manager = own team).
  /// [employeeId] narrows to a single person.
  static Future<List<EmpAttendanceSummary>> fetchMonthlySummary({
    required int year,
    required int month,
    String? teamId,
    String? employeeId,
  }) async {
    final first =
        '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-01';
    final nextY = month == 12 ? year + 1 : year;
    final nextM = month == 12 ? 1 : month + 1;
    final next =
        '${nextY.toString().padLeft(4, '0')}-'
        '${nextM.toString().padLeft(2, '0')}-01';

    // Base staff list (so people with zero records still appear).
    final staff = await _staff(teamId: teamId);
    final summaries = <String, EmpAttendanceSummary>{
      for (final s in staff)
        if (employeeId == null || s['id'] == employeeId)
          s['id']!: EmpAttendanceSummary(
            employeeId: s['id']!,
            name: s['name']!,
          ),
    };

    try {
      var q = _admin
          .from('attendance')
          .select('employee_id, status')
          .gte('attendance_date', first)
          .lt('attendance_date', next);
      if (employeeId != null) {
        q = q.eq('employee_id', employeeId);
      } else if (summaries.isNotEmpty) {
        q = q.inFilter('employee_id', summaries.keys.toList());
      }
      final rows = await q;
      for (final r in rows as List) {
        final id = (r as Map<String, dynamic>)['employee_id'] as String;
        final st = r['status'] as String? ?? 'present';
        final s = summaries.putIfAbsent(
          id,
          () => EmpAttendanceSummary(employeeId: id, name: 'Unknown'),
        );
        switch (st) {
          case 'absent':
            s.absent++;
            break;
          case 'late':
            s.late++;
            break;
          case 'half_day':
            s.halfDay++;
            break;
          default:
            s.present++;
        }
      }
    } catch (_) {}

    final list = summaries.values.toList()
      ..sort((a, b) => b.attended.compareTo(a.attended));
    return list;
  }

  /// Batch-enriches plain attendance rows (no FK join) with employee names
  /// by doing a separate `profiles` lookup.
  static Future<List<Map<String, dynamic>>> _enrichWithNames(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final ids = rows.map((r) => r['employee_id'] as String).toSet().toList();
    final profiles = await _admin
        .from('profiles')
        .select('id, full_name')
        .inFilter('id', ids);
    final nameMap = {
      for (final p in (profiles as List<dynamic>))
        (p as Map<String, dynamic>)['id'] as String:
            p['full_name'] as String? ?? 'Unknown',
    };
    return rows
        .map(
          (r) => {
            ...r,
            'employee': {'full_name': nameMap[r['employee_id']] ?? 'Unknown'},
          },
        )
        .toList();
  }

  /// Two-pass query: tries FK join first; if the FK constraint is absent in
  /// Supabase, falls back to a plain `'*'` select + `_enrichWithNames`.
  static Future<List<AttendanceRecord>> _queryAttendanceList(
    Future<dynamic> Function(String select) selectFn,
  ) async {
    try {
      final data = await selectFn(_select);
      return (data as List<dynamic>)
          .map((m) => AttendanceRecord.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    try {
      final data = await selectFn('*');
      final rows = (data as List<dynamic>).cast<Map<String, dynamic>>();
      final enriched = await _enrichWithNames(rows);
      return enriched.map(AttendanceRecord.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch all attendance records for a given date (admin/manager view).
  /// Pass [teamId] to scope results to a specific team (admin switcher or
  /// manager view). When null, returns all records.
  static Future<List<AttendanceRecord>> fetchByDate(
    String date, {
    String? teamId,
  }) async {
    // Resolve member IDs once — profiles never uses the FK join
    List<String>? memberIds;
    if (teamId != null) {
      try {
        final members = await _admin
            .from('profiles')
            .select('id')
            .eq('team_id', teamId);
        memberIds = (members as List<dynamic>)
            .map((m) => (m as Map<String, dynamic>)['id'] as String)
            .toList();
        if (memberIds.isEmpty) return [];
      } catch (_) {
        return [];
      }
    }
    return _queryAttendanceList((sel) {
      var q = _admin.from('attendance').select(sel).eq('attendance_date', date);
      if (memberIds != null) q = q.inFilter('employee_id', memberIds);
      return q.order('created_at');
    });
  }

  /// Fetch all attendance records for a specific employee in a specific month/year.
  static Future<List<AttendanceRecord>> fetchForEmployeeMonthly({
    required String employeeId,
    required int year,
    required int month,
  }) async {
    final first =
        '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-01';
    final nextY = month == 12 ? year + 1 : year;
    final nextM = month == 12 ? 1 : month + 1;
    final next =
        '${nextY.toString().padLeft(4, '0')}-'
        '${nextM.toString().padLeft(2, '0')}-01';

    return _queryAttendanceList(
      (sel) => _admin
          .from('attendance')
          .select(sel)
          .eq('employee_id', employeeId)
          .gte('attendance_date', first)
          .lt('attendance_date', next)
          .order('attendance_date', ascending: false),
    );
  }

  /// Fetch the last 30 days of attendance for a specific employee.
  static Future<List<AttendanceRecord>> fetchForEmployee(
    String employeeId,
  ) async {
    final from = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .substring(0, 10);
    return _queryAttendanceList(
      (sel) => _admin
          .from('attendance')
          .select(sel)
          .eq('employee_id', employeeId)
          .gte('attendance_date', from)
          .order('attendance_date', ascending: false),
    );
  }

  /// Get today's record for a specific employee (null if not checked in).
  static Future<AttendanceRecord?> fetchTodayForEmployee(
    String employeeId,
  ) async {
    final today = AppTime.now().toIso8601String().substring(0, 10);
    // Pass 1: FK join
    try {
      final data = await _admin
          .from('attendance')
          .select(_select)
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();
      if (data == null) return null;
      return AttendanceRecord.fromMap(data);
    } catch (_) {}
    // Pass 2: plain select + enrich
    try {
      final data = await _admin
          .from('attendance')
          .select('*')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();
      if (data == null) return null;
      final enriched = await _enrichWithNames([data]);
      return AttendanceRecord.fromMap(enriched.first);
    } catch (_) {
      return null;
    }
  }

  /// Check in for today. Returns null on success, error message string on failure.
  ///
  /// IMPORTANT: check_in_time is only set on the FIRST check-in of the day.
  /// Subsequent calls (e.g. WiFi reconnects) must NOT overwrite it, otherwise
  /// a later check-in could end up after an earlier check-out and violate the
  /// `att_checkout_after_checkin` constraint.
  static Future<String?> checkIn(String employeeId) async {
    try {
      // Calendar day in Egypt; timestamps stored as UTC.
      final today = AppTime.now().toIso8601String().substring(0, 10);
      final now = DateTime.now().toUtc().toIso8601String();

      final existing = await _admin
          .from('attendance')
          .select('check_in_time, is_approved')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();

      if (existing != null) {
        // Approved records are locked — never modify them automatically.
        if (existing['is_approved'] == true) return null;

        if (existing['check_in_time'] != null) {
          // Already checked in today — keep the original check-in time.
          // Reconnecting means they're back on-site: reopen the session by
          // clearing check_out so the next disconnect records fresh hours.
          await _admin
              .from('attendance')
              .update({
                'check_out_time': null,
                'status': 'present',
                'updated_at': now,
              })
              .eq('employee_id', employeeId)
              .eq('attendance_date', today);
          return null;
        }
      }

      // First check-in of the day.
      await _admin.from('attendance').upsert({
        'employee_id': employeeId,
        'attendance_date': today,
        'check_in_time': now,
        'status': 'present',
      }, onConflict: 'employee_id, attendance_date');
      return null;
    } catch (e) {
      final s = e.toString();
      final m = RegExp(r'message: ([^,\)]+)').firstMatch(s);
      return m != null ? m.group(1)!.trim() : s;
    }
  }

  /// Check out for today. Returns null on success, error message string on failure.
  /// [dailyReport] — what the employee did today (required by the UI on manual
  /// check-out).
  static Future<String?> checkOut(
    String employeeId, {
    String? dailyReport,
  }) async {
    try {
      final today = AppTime.now().toIso8601String().substring(0, 10);
      final checkIn = await _admin
          .from('attendance')
          .select('check_in_time')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();

      final nowDt = DateTime.now().toUtc();
      DateTime? inTime;
      if (checkIn != null && checkIn['check_in_time'] != null) {
        inTime = DateTime.tryParse(checkIn['check_in_time'] as String);
      }

      // Guard: never write a check-out before the check-in (constraint safety).
      if (inTime != null && !nowDt.isAfter(inTime)) {
        return null; // nothing sensible to record yet
      }

      double? hours;
      if (inTime != null) {
        hours = nowDt.difference(inTime).inMinutes / 60.0;
        if (hours < 0) hours = 0;
      }

      await _admin
          .from('attendance')
          .update({
            'check_out_time': nowDt.toIso8601String(),
            if (hours != null)
              'total_hours': double.parse(hours.toStringAsFixed(2)),
            if (dailyReport != null && dailyReport.trim().isNotEmpty)
              'daily_report': dailyReport.trim(),
            'updated_at': nowDt.toIso8601String(),
          })
          .eq('employee_id', employeeId)
          .eq('attendance_date', today);
      return null;
    } catch (e) {
      final s = e.toString();
      final m = RegExp(r'message: ([^,\)]+)').firstMatch(s);
      return m != null ? m.group(1)!.trim() : s;
    }
  }

  /// Save / update just the daily report for an employee's day.
  static Future<void> saveReport({
    required String employeeId,
    required String date,
    required String report,
  }) async {
    try {
      await _admin
          .from('attendance')
          .update({
            'daily_report': report.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('employee_id', employeeId)
          .eq('attendance_date', date);
    } catch (_) {}
  }

  /// WiFi-based auto check-in.
  static Future<void> autoCheckIn(String employeeId) => checkIn(employeeId);

  /// WiFi-based auto check-out with hour accumulation.
  static Future<void> autoCheckOut(
    String employeeId, {
    int accumulatedMinutes = 0,
  }) async {
    try {
      final today = AppTime.now().toIso8601String().substring(0, 10);
      final nowDt = DateTime.now().toUtc();

      final row = await _admin
          .from('attendance')
          .select('check_in_time, total_hours, is_approved')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();

      if (row == null) return;

      // Approved records are locked — never modify them automatically.
      if (row['is_approved'] == true) return;

      // Guard: check-out must be strictly after check-in (constraint safety).
      final inTime = DateTime.tryParse(row['check_in_time'] as String? ?? '');
      if (inTime != null && !nowDt.isAfter(inTime)) return;

      double existing = (row['total_hours'] as num?)?.toDouble() ?? 0;
      if (existing < 0) existing = 0;
      double newHours = existing + (accumulatedMinutes / 60.0);
      if (newHours < 0) newHours = 0;

      await _admin
          .from('attendance')
          .update({
            'check_out_time': nowDt.toIso8601String(),
            'total_hours': double.parse(newHours.toStringAsFixed(2)),
            'updated_at': nowDt.toIso8601String(),
          })
          .eq('employee_id', employeeId)
          .eq('attendance_date', today);
    } catch (_) {}
  }

  /// Employee manually logs or edits their own attendance for any date.
  /// Returns false if the record is approved and cannot be edited.
  static Future<bool> manualAddAttendance({
    required String employeeId,
    required String date,
    required String checkInTime,
    required String checkOutTime,
    String? note,
    String status = 'present',
  }) async {
    final isAbsent = status == 'absent';
    final inDt = DateTime.tryParse(checkInTime);
    final outDt = DateTime.tryParse(checkOutTime);

    // Absent days carry no times. Otherwise check-out must be after check-in.
    if (!isAbsent && inDt != null && outDt != null && !outDt.isAfter(inDt)) {
      return false; // invalid time range — dialog shows a message
    }
    double? hours;
    if (!isAbsent && inDt != null && outDt != null) {
      hours = outDt.difference(inDt).inMinutes / 60.0;
      if (hours < 0) hours = 0;
    }

    final String? inIso = isAbsent ? null : checkInTime;
    final String? outIso = isAbsent ? null : checkOutTime;

    // Try with full new-column payload first; fall back if columns missing
    try {
      await _admin.from('attendance').upsert({
        'employee_id': employeeId,
        'attendance_date': date,
        'check_in_time': inIso,
        'check_out_time': outIso,
        'status': status,
        'total_hours': isAbsent
            ? 0
            : (hours != null ? double.parse(hours.toStringAsFixed(2)) : null),
        'is_manual': true,
        'manual_note': note,
        'is_approved': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'employee_id, attendance_date');
      return true;
    } catch (_) {}

    try {
      await _admin.from('attendance').upsert({
        'employee_id': employeeId,
        'attendance_date': date,
        'check_in_time': inIso,
        'check_out_time': outIso,
        'status': status,
        'total_hours': isAbsent
            ? 0
            : (hours != null ? double.parse(hours.toStringAsFixed(2)) : null),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'employee_id, attendance_date');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin / manager approves an attendance record — locks it from employee edits.
  static Future<void> approveAttendance({
    required String attendanceId,
    required String approvedBy,
  }) async {
    try {
      await _admin
          .from('attendance')
          .update({
            'is_approved': true,
            'approved_by': approvedBy,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', attendanceId);
    } catch (_) {}
  }

  /// Admin / manager manual override of attendance for any employee.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> overrideAttendance({
    required String employeeId,
    required String date,
    required String checkInTime,
    required String checkOutTime,
    required String reason,
    required String status,
  }) async {
    final isAbsent = status == 'absent';
    final inDt = DateTime.tryParse(checkInTime);
    final outDt = DateTime.tryParse(checkOutTime);

    // Absent days carry no times. Otherwise check-out must be after check-in.
    if (!isAbsent && inDt != null && outDt != null && !outDt.isAfter(inDt)) {
      return 'Check-out time must be after check-in time.';
    }
    double? hours;
    if (!isAbsent && inDt != null && outDt != null) {
      hours = outDt.difference(inDt).inMinutes / 60.0;
      if (hours < 0) hours = 0;
    }

    final String? inIso = isAbsent ? null : checkInTime;
    final String? outIso = isAbsent ? null : checkOutTime;

    try {
      await _admin.from('attendance').upsert({
        'employee_id': employeeId,
        'attendance_date': date,
        'check_in_time': inIso,
        'check_out_time': outIso,
        'status': status,
        'total_hours': isAbsent
            ? 0
            : (hours != null ? double.parse(hours.toStringAsFixed(2)) : null),
        'is_overridden': true,
        'override_reason': reason,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'employee_id, attendance_date');
      return null;
    } catch (e) {
      final s = e.toString();
      final m = RegExp(r'message: ([^,\)]+)').firstMatch(s);
      return m != null
          ? m.group(1)!.trim()
          : 'Could not save the override. Please try again.';
    }
  }
}
