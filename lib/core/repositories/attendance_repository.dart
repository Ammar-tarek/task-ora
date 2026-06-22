// lib/core/repositories/attendance_repository.dart

import '../services/supabase_service.dart';

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
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) {
    final profile = m['employee'] as Map<String, dynamic>?;
    return AttendanceRecord(
      id:             m['id'] as String,
      employeeId:     m['employee_id'] as String,
      employeeName:   profile?['full_name'] as String? ?? 'Unknown',
      date:           m['attendance_date'] as String? ?? '',
      checkInTime:    m['check_in_time'] as String?,
      checkOutTime:   m['check_out_time'] as String?,
      status:         m['status'] as String? ?? 'present',
      totalHours:     (m['total_hours'] as num?)?.toDouble(),
      isOverridden:   m['is_overridden'] as bool? ?? false,
      overrideReason: m['override_reason'] as String?,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'present':  return 'Present';
      case 'absent':   return 'Absent';
      case 'late':     return 'Late';
      case 'half_day': return 'Half Day';
      default:         return status;
    }
  }

  bool get isCheckedIn  => checkInTime != null;
  bool get isCheckedOut => checkOutTime != null;
}

class AttendanceRepository {
  static final _client = SupabaseService.client;
  static final _admin  = SupabaseService.adminClient;

  static const _select = '*, employee:profiles(full_name)';

  /// Fetch all attendance records for a given date (admin/manager view).
  static Future<List<AttendanceRecord>> fetchByDate(String date) async {
    try {
      final data = await _admin
          .from('attendance')
          .select(_select)
          .eq('attendance_date', date)
          .order('created_at');
      return (data as List).map((m) => AttendanceRecord.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch the last 30 days of attendance for a specific employee.
  static Future<List<AttendanceRecord>> fetchForEmployee(String employeeId) async {
    try {
      final from = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10);
      final data = await _client
          .from('attendance')
          .select(_select)
          .eq('employee_id', employeeId)
          .gte('attendance_date', from)
          .order('attendance_date', ascending: false);
      return (data as List).map((m) => AttendanceRecord.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get today's record for a specific employee (null if not checked in).
  static Future<AttendanceRecord?> fetchTodayForEmployee(String employeeId) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final data  = await _client
          .from('attendance')
          .select(_select)
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();
      if (data == null) return null;
      return AttendanceRecord.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Check in for today.
  static Future<void> checkIn(String employeeId) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await _client.from('attendance').upsert({
        'employee_id':     employeeId,
        'attendance_date': today,
        'check_in_time':   DateTime.now().toIso8601String(),
        'status':          'present',
      }, onConflict: 'employee_id, attendance_date');
    } catch (_) {}
  }

  /// Check out for today.
  static Future<void> checkOut(String employeeId) async {
    try {
      final today     = DateTime.now().toIso8601String().substring(0, 10);
      final checkIn   = await _client
          .from('attendance')
          .select('check_in_time')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();

      double? hours;
      if (checkIn != null && checkIn['check_in_time'] != null) {
        final inTime = DateTime.tryParse(checkIn['check_in_time'] as String);
        if (inTime != null) {
          hours = DateTime.now().difference(inTime).inMinutes / 60.0;
        }
      }

      await _client.from('attendance').update({
        'check_out_time': DateTime.now().toIso8601String(),
        if (hours != null) 'total_hours': double.parse(hours.toStringAsFixed(2)),
        'updated_at':     DateTime.now().toIso8601String(),
      })
      .eq('employee_id', employeeId)
      .eq('attendance_date', today);
    } catch (_) {}
  }

  /// WiFi-based auto check-in: same as checkIn but marks source.
  static Future<void> autoCheckIn(String employeeId) => checkIn(employeeId);

  /// WiFi-based auto check-out with hour accumulation.
  /// [accumulatedMinutes] are added to any existing total_hours.
  static Future<void> autoCheckOut(String employeeId, {int accumulatedMinutes = 0}) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final row = await _client
          .from('attendance')
          .select('check_in_time, total_hours')
          .eq('employee_id', employeeId)
          .eq('attendance_date', today)
          .maybeSingle();

      if (row == null) return;

      double existing = (row['total_hours'] as num?)?.toDouble() ?? 0;
      double newHours = existing + (accumulatedMinutes / 60.0);

      await _client.from('attendance').update({
        'check_out_time': DateTime.now().toIso8601String(),
        'total_hours':    double.parse(newHours.toStringAsFixed(2)),
        'updated_at':     DateTime.now().toIso8601String(),
      })
      .eq('employee_id', employeeId)
      .eq('attendance_date', today);
    } catch (_) {}
  }

  /// Admin / manager manual override of attendance for any employee.
  static Future<void> overrideAttendance({
    required String employeeId,
    required String date,
    required String checkInTime,
    required String checkOutTime,
    required String reason,
    required String status,
  }) async {
    try {
      final inDt  = DateTime.tryParse(checkInTime);
      final outDt = DateTime.tryParse(checkOutTime);
      double? hours;
      if (inDt != null && outDt != null) {
        hours = outDt.difference(inDt).inMinutes / 60.0;
      }

      await _admin.from('attendance').upsert({
        'employee_id':     employeeId,
        'attendance_date': date,
        'check_in_time':   checkInTime,
        'check_out_time':  checkOutTime,
        'status':          status,
        if (hours != null) 'total_hours': double.parse(hours.toStringAsFixed(2)),
        'is_overridden':   true,
        'override_reason': reason,
        'updated_at':      DateTime.now().toIso8601String(),
      }, onConflict: 'employee_id, attendance_date');
    } catch (_) {}
  }
}
