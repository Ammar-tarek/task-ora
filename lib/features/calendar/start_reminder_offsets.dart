// lib/features/calendar/start_reminder_offsets.dart
// Pure rules for configurable event START-time reminders. Mirrors the server
// logic in PROPOSED_phase1_event_start_reminders.sql so it is unit-testable.
// Timezone-safe: callers pass real DateTimes (compare in UTC); offsets are
// whole minutes before start. Distinct from the existing END-time reminders.

class StartReminderOffsets {
  StartReminderOffsets._();

  /// Allowed offsets in minutes before start: at time, 5, 10, 15, 30, 60, 1 day.
  static const List<int> allowed = [0, 5, 10, 15, 30, 60, 1440];

  static bool isAllowed(int offset) => allowed.contains(offset);

  /// Human label for an offset.
  static String label(int offset) {
    switch (offset) {
      case 0:
        return 'At event time';
      case 60:
        return '1 hour before';
      case 1440:
        return '1 day before';
      default:
        return '$offset minutes before';
    }
  }

  /// The moment a reminder for [offset] should fire for an event at [start].
  static DateTime dueAt(DateTime start, int offset) =>
      start.subtract(Duration(minutes: offset));

  /// True when the reminder is due at [now]: now has reached (start - offset)
  /// and is still within one minute of start (so the "at event time" / offset 0
  /// reminder fires in the minute of start instead of an empty window).
  /// Compared in UTC to stay tz-safe. The server dedup log fires it only once.
  static bool isDue({
    required DateTime start,
    required int offset,
    required DateTime now,
  }) {
    final s = start.toUtc();
    final n = now.toUtc();
    return !n.isBefore(dueAt(s, offset)) &&
        n.isBefore(s.add(const Duration(minutes: 1)));
  }

  /// Idempotency key — one delivery per (event, recipient, offset).
  static String dedupKey(String eventId, String profileId, int offset) =>
      '$eventId:$profileId:$offset';

  /// Keep only valid, de-duplicated offsets, sorted.
  static List<int> normalize(Iterable<int> offsets) {
    final set = offsets.where(isAllowed).toSet().toList()..sort();
    return set;
  }

  /// Parse raw `event_start_reminder_offsets` rows into normalized offsets.
  static List<int> parseRows(List<dynamic> rows) => normalize(
        rows.map((r) => (r as Map)['offset_minutes'] as int),
      );
}

/// Result of loading an event's start-reminder offsets. Distinguishes a
/// legitimate empty list (loaded, no reminders) from a READ FAILURE, so the UI
/// never shows "no reminders" when the load actually failed, and never
/// overwrites existing settings from an unknown state.
class ReminderLoadResult {
  final List<int>? offsets; // non-null = loaded (may be empty)
  final String? error; // non-null = read failed

  const ReminderLoadResult.ok(List<int> loaded)
      : offsets = loaded,
        error = null;
  const ReminderLoadResult.failed(String message)
      : offsets = null,
        error = message;

  bool get ok => error == null;
}
