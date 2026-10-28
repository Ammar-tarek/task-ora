// test/start_reminder_offsets_test.dart
// Start-time reminder rules: scheduling window, dedup, reschedule, tz boundary.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/features/calendar/start_reminder_offsets.dart';

void main() {
  group('allowed offsets', () {
    test('exactly the agreed set', () {
      expect(StartReminderOffsets.allowed, [0, 5, 10, 15, 30, 60, 1440]);
      expect(StartReminderOffsets.isAllowed(45), isFalse);
      expect(StartReminderOffsets.isAllowed(1440), isTrue);
    });

    test('normalize drops bad + dupes, sorts', () {
      expect(StartReminderOffsets.normalize([60, 5, 5, 99, 10]), [5, 10, 60]);
    });

    test('empty list stays empty (intentional "clear all reminders")', () {
      expect(StartReminderOffsets.normalize([]), isEmpty);
    });

    test('all-invalid offsets normalize to empty (nothing persisted)', () {
      expect(StartReminderOffsets.normalize([45, -1, 1441]), isEmpty);
    });

    test('labels', () {
      expect(StartReminderOffsets.label(0), 'At event time');
      expect(StartReminderOffsets.label(15), '15 minutes before');
      expect(StartReminderOffsets.label(60), '1 hour before');
      expect(StartReminderOffsets.label(1440), '1 day before');
    });
  });

  group('load result: empty read vs failed read', () {
    test('parseRows: empty rows → empty offsets (legitimate "no reminders")', () {
      expect(StartReminderOffsets.parseRows(const []), isEmpty);
    });

    test('parseRows: parses + normalizes (drops invalid, sorts, dedupes)', () {
      final rows = [
        {'offset_minutes': 15},
        {'offset_minutes': 5},
        {'offset_minutes': 5},
        {'offset_minutes': 99}, // invalid → dropped
      ];
      expect(StartReminderOffsets.parseRows(rows), [5, 15]);
    });

    test('ok([]) is a SUCCESSFUL empty read, not a failure', () {
      const r = ReminderLoadResult.ok(<int>[]);
      expect(r.ok, isTrue);
      expect(r.offsets, isEmpty);
      expect(r.error, isNull);
    });

    test('ok([5,15]) exposes the loaded offsets', () {
      const r = ReminderLoadResult.ok([5, 15]);
      expect(r.ok, isTrue);
      expect(r.offsets, [5, 15]);
    });

    test('failed(msg) is NOT ok and carries no offsets', () {
      const r = ReminderLoadResult.failed('boom');
      expect(r.ok, isFalse);
      expect(r.offsets, isNull);
      expect(r.error, 'boom');
    });
  });

  group('isDue scheduling window', () {
    final start = DateTime.utc(2026, 10, 27, 12, 0); // event at 12:00 UTC

    test('not due before the window opens', () {
      // 15-min reminder opens at 11:45. At 11:44 → not due.
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 15,
          now: DateTime.utc(2026, 10, 27, 11, 44),
        ),
        isFalse,
      );
    });

    test('due once inside the window, before start', () {
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 15,
          now: DateTime.utc(2026, 10, 27, 11, 46),
        ),
        isTrue,
      );
    });

    test('not due after the event has started', () {
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 15,
          now: DateTime.utc(2026, 10, 27, 12, 1),
        ),
        isFalse,
      );
    });

    test('"at event time" (0) fires in the minute at start, not before', () {
      // Before start → not yet due.
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 0,
          now: DateTime.utc(2026, 10, 27, 11, 59),
        ),
        isFalse,
      );
      // At start → due.
      expect(
        StartReminderOffsets.isDue(start: start, offset: 0, now: start),
        isTrue,
      );
      // One minute after start → window closed.
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 0,
          now: DateTime.utc(2026, 10, 27, 12, 1),
        ),
        isFalse,
      );
    });

    test('1-day reminder opens 24h before', () {
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 1440,
          now: DateTime.utc(2026, 10, 26, 12, 0),
        ),
        isTrue,
      );
      expect(
        StartReminderOffsets.isDue(
          start: start,
          offset: 1440,
          now: DateTime.utc(2026, 10, 26, 11, 59),
        ),
        isFalse,
      );
    });
  });

  group('timezone boundary', () {
    test('local-time now is compared in UTC (no off-by-tz)', () {
      // Event at 10:00 UTC. A local +02:00 clock reading 11:46 == 09:46 UTC,
      // still before the 15-min window (09:45 UTC) by one minute → due.
      final start = DateTime.utc(2026, 10, 27, 10, 0);
      final nowLocalPlus2 = DateTime.parse('2026-10-27T11:46:00+02:00');
      expect(
        StartReminderOffsets.isDue(start: start, offset: 15, now: nowLocalPlus2),
        isTrue,
      );
    });
  });

  group('dedup + reschedule', () {
    test('dedup key is stable per (event, recipient, offset)', () {
      final a = StartReminderOffsets.dedupKey('e1', 'u1', 15);
      final b = StartReminderOffsets.dedupKey('e1', 'u1', 15);
      final c = StartReminderOffsets.dedupKey('e1', 'u1', 30);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('reschedule clears delivery → reminder can re-evaluate', () {
      // Simulate the server trigger: moving start wipes the sent log, so a new
      // due window is honoured instead of staying marked as sent.
      final sent = <String>{StartReminderOffsets.dedupKey('e1', 'u1', 15)};
      // start_time changed → clear this event's log rows.
      sent.removeWhere((k) => k.startsWith('e1:'));
      expect(sent, isEmpty);
    });
  });
}
