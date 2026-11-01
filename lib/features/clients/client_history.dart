// lib/features/clients/client_history.dart
// Pure, UI-free logic for a client's calendar history: grouping events into
// months and navigating between them. Kept Flutter-free so it is unit-testable.
// The event list passed in is whatever ClientRepository.fetchClientEvents
// returned — i.e. already RLS-scoped; this never fetches or widens visibility.

import '../../core/repositories/client_repository.dart' show CalEventData;

/// A calendar month (year + 1..12), with ordered navigation.
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month; // 1..12
  const YearMonth(this.year, this.month);

  factory YearMonth.of(DateTime d) => YearMonth(d.year, d.month);

  /// The month before this one, rolling the year at January.
  YearMonth get previous =>
      month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);

  /// The month after this one, rolling the year at December.
  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  /// True when [d] falls in this calendar month (time of day ignored).
  bool covers(DateTime d) => d.year == year && d.month == month;

  @override
  int compareTo(YearMonth other) => year != other.year
      ? year.compareTo(other.year)
      : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => year * 100 + month;

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

class ClientHistory {
  ClientHistory._();

  /// Events whose START falls in [ym], earliest first.
  static List<CalEventData> eventsInMonth(
    List<CalEventData> events,
    YearMonth ym,
  ) {
    final list = events.where((e) => ym.covers(e.start)).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  /// Distinct months that contain at least one event, newest first.
  static List<YearMonth> monthsWithEvents(List<CalEventData> events) {
    final set = <YearMonth>{for (final e in events) YearMonth.of(e.start)};
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// All events sorted by start time; most-recent first by default.
  static List<CalEventData> chronological(
    List<CalEventData> events, {
    bool descending = true,
  }) {
    final list = [...events];
    list.sort(
      (a, b) => descending ? b.start.compareTo(a.start) : a.start.compareTo(b.start),
    );
    return list;
  }

  /// The month to open on: the most recent month that has events, or
  /// [fallback] (default: today's month) when there are none.
  static YearMonth initialMonth(
    List<CalEventData> events, {
    DateTime? fallback,
  }) {
    final months = monthsWithEvents(events);
    if (months.isNotEmpty) return months.first;
    final f = fallback ?? DateTime.now();
    return YearMonth(f.year, f.month);
  }
}
