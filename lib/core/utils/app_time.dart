// lib/core/utils/app_time.dart
// Forces all user-facing times to Egypt (Africa/Cairo), independent of the
// device timezone. Egypt observes DST since 2023: +03:00 from the last Friday
// of April to the last Thursday of October, otherwise +02:00.

class AppTime {
  static const _std = Duration(hours: 2); // EET
  static const _dst = Duration(hours: 3); // EEST

  /// Convert any DateTime to Egypt local time.
  static DateTime cairo(DateTime dt) {
    final u = dt.toUtc();
    return u.add(_isDst(u) ? _dst : _std);
  }

  /// Egypt "now".
  static DateTime now() => cairo(DateTime.now());

  /// 12-hour time like "3:05 PM".
  static String hm(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ap';
  }

  /// Convert an Egypt wall-clock time (what the user picked) to a UTC
  /// DateTime for storage. Inverse of [cairo].
  static DateTime fromCairoToUtc(int y, int m, int d, int h, int min) {
    // First guess with standard offset, then re-check DST at that instant.
    var utc = DateTime.utc(y, m, d, h, min).subtract(_std);
    if (_isDst(utc)) utc = DateTime.utc(y, m, d, h, min).subtract(_dst);
    return utc;
  }

  /// 12-hour time for a TimeOfDay-like (hour/minute) input.
  static String hm2(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final ap = hour < 12 ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $ap';
  }

  static bool _isDst(DateTime u) {
    final y = u.year;
    final start = _lastWeekday(y, 4, DateTime.friday);   // last Fri Apr, 00:00 UTC-ish
    final end   = _lastWeekday(y, 10, DateTime.thursday); // last Thu Oct
    return u.isAfter(start) && u.isBefore(end);
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    var d = DateTime.utc(year, month + 1, 0); // last day of month
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return DateTime.utc(year, d.month, d.day);
  }
}
