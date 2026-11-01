// test/client_history_test.dart
// Phase B — client calendar history grouping + month navigation.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/repositories/client_repository.dart';
import 'package:task_ora/features/clients/client_history.dart';

CalEventData _ev(String id, DateTime start, {String status = 'pending'}) =>
    CalEventData(
      id: id,
      title: 'E$id',
      start: start,
      end: start.add(const Duration(hours: 1)),
      status: status,
    );

void main() {
  group('YearMonth navigation', () {
    test('previous rolls back across January', () {
      expect(const YearMonth(2026, 1).previous, const YearMonth(2025, 12));
    });
    test('next rolls forward across December', () {
      expect(const YearMonth(2026, 12).next, const YearMonth(2027, 1));
    });
    test('covers matches only same year+month, ignoring day/time', () {
      const ym = YearMonth(2026, 10);
      expect(ym.covers(DateTime(2026, 10, 1, 0, 0)), isTrue);
      expect(ym.covers(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(ym.covers(DateTime(2026, 11, 1)), isFalse);
      expect(ym.covers(DateTime(2025, 10, 15)), isFalse);
    });
  });

  group('ClientHistory.eventsInMonth', () {
    final events = [
      _ev('1', DateTime(2026, 10, 5, 9)),
      _ev('2', DateTime(2026, 10, 20, 14)),
      _ev('3', DateTime(2026, 11, 2, 10)),
      _ev('4', DateTime(2026, 9, 30, 12)),
    ];

    test('returns only that month, earliest first', () {
      final r = ClientHistory.eventsInMonth(events, const YearMonth(2026, 10));
      expect(r.map((e) => e.id), ['1', '2']);
    });
    test('empty for a month with no events', () {
      expect(
        ClientHistory.eventsInMonth(events, const YearMonth(2026, 12)),
        isEmpty,
      );
    });
  });

  group('ClientHistory.monthsWithEvents', () {
    test('distinct months, newest first', () {
      final events = [
        _ev('1', DateTime(2026, 10, 5)),
        _ev('2', DateTime(2026, 10, 20)),
        _ev('3', DateTime(2026, 11, 2)),
        _ev('4', DateTime(2026, 9, 30)),
      ];
      expect(
        ClientHistory.monthsWithEvents(events),
        [const YearMonth(2026, 11), const YearMonth(2026, 10), const YearMonth(2026, 9)],
      );
    });
    test('empty list yields no months', () {
      expect(ClientHistory.monthsWithEvents([]), isEmpty);
    });
  });

  group('ClientHistory.chronological', () {
    final events = [
      _ev('1', DateTime(2026, 10, 5)),
      _ev('2', DateTime(2026, 11, 2)),
      _ev('3', DateTime(2026, 9, 30)),
    ];
    test('descending (most recent first) by default', () {
      expect(ClientHistory.chronological(events).map((e) => e.id), ['2', '1', '3']);
    });
    test('ascending when requested', () {
      expect(
        ClientHistory.chronological(events, descending: false).map((e) => e.id),
        ['3', '1', '2'],
      );
    });
  });

  group('ClientHistory.initialMonth', () {
    test('most recent month with events', () {
      final events = [
        _ev('1', DateTime(2026, 8, 5)),
        _ev('2', DateTime(2026, 10, 2)),
      ];
      expect(ClientHistory.initialMonth(events), const YearMonth(2026, 10));
    });
    test('falls back to the given month when there are no events', () {
      expect(
        ClientHistory.initialMonth([], fallback: DateTime(2026, 3, 15)),
        const YearMonth(2026, 3),
      );
    });
  });
}
