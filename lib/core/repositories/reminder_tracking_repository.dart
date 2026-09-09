// lib/core/repositories/reminder_tracking_repository.dart
//
// Read model for the attendance-reminder tracking screen. Reads go through the
// SECURITY DEFINER RPC `get_reminder_tracking`, called on the ANON client so
// the caller's JWT (auth.uid()) drives server-side team scoping — a manager
// can only ever receive their own team's rows, regardless of client input.

import '../services/supabase_service.dart';

/// Outcome of a reminder for one employee on one day.
enum ReminderStatus {
  checkedInAfter,     // reminder sent, checked in AFTER it
  checkedInBefore,    // reminder sent, but check-in was before it (rare)
  stillAbsent,        // reminder sent, no check-in yet
  checkedInNoReminder,// no reminder (checked in before 12 PM), present
  noReminder,         // no reminder and no check-in
}

class ReminderTrackingRow {
  final String employeeId;
  final String fullName;
  final String? teamId;
  final String? teamName;
  final DateTime? reminderSentAt;      // UTC
  final DateTime? checkedInAt;         // UTC (from reminder row)
  final bool checkedInAfterReminder;
  final DateTime? attendanceCheckInTime; // UTC (authoritative check-in)

  const ReminderTrackingRow({
    required this.employeeId,
    required this.fullName,
    this.teamId,
    this.teamName,
    this.reminderSentAt,
    this.checkedInAt,
    required this.checkedInAfterReminder,
    this.attendanceCheckInTime,
  });

  bool get reminderSent => reminderSentAt != null;
  DateTime? get checkIn => attendanceCheckInTime ?? checkedInAt;

  ReminderStatus get status {
    if (reminderSent) {
      if (checkIn != null) {
        return checkedInAfterReminder
            ? ReminderStatus.checkedInAfter
            : ReminderStatus.checkedInBefore;
      }
      return ReminderStatus.stillAbsent;
    }
    return checkIn != null
        ? ReminderStatus.checkedInNoReminder
        : ReminderStatus.noReminder;
  }

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  factory ReminderTrackingRow.fromMap(Map<String, dynamic> m) =>
      ReminderTrackingRow(
        employeeId: m['employee_id'] as String,
        fullName: m['full_name'] as String? ?? 'Unknown',
        teamId: m['team_id'] as String?,
        teamName: m['team_name'] as String?,
        reminderSentAt: _dt(m['reminder_sent_at']),
        checkedInAt: _dt(m['checked_in_at']),
        checkedInAfterReminder: m['checked_in_after_reminder'] as bool? ?? false,
        attendanceCheckInTime: _dt(m['attendance_check_in_time']),
      );
}

class ReminderTrackingRepository {
  /// Anon client — carries the signed-in user's JWT so the RPC can scope by
  /// role/team. Do NOT use the service-role admin client here (it bypasses the
  /// server-side access control this feature relies on).
  static final _client = SupabaseService.client;

  /// Fetch tracking rows for [date]. [teamId] is honoured only for admins
  /// (managers are always restricted to their own team server-side).
  static Future<List<ReminderTrackingRow>> fetch({
    required DateTime date,
    String? teamId,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_date': date.toIso8601String().substring(0, 10),
      };
      if (teamId != null) params['p_team_id'] = teamId;

      final data = await _client.rpc('get_reminder_tracking', params: params);
      return (data as List)
          .map((m) => ReminderTrackingRow.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Manually send a reminder now to everyone currently not checked in.
  /// Scope is enforced server-side: managers hit only their own team; admins
  /// hit everyone, or one [teamId]. Returns how many people were reminded.
  static Future<int> sendManual({String? teamId}) async {
    final params = <String, dynamic>{};
    if (teamId != null) params['p_team_id'] = teamId;
    final res =
        await _client.rpc('send_manual_attendance_reminders', params: params);
    if (res is int) return res;
    return int.tryParse('$res') ?? 0;
  }
}
