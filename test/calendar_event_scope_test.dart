// test/calendar_event_scope_test.dart
// Verifies the pure rules for department-aware calendar event creation:
// Studio events become room bookings (so the DB overlap constraint applies),
// every other department uses the default event type.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/constants/departments.dart';
import 'package:task_ora/core/services/calendar_event_scope.dart';

void main() {
  group('CalendarEventScope.eventTypeForDepartment', () {
    test('Studio events are room bookings', () {
      expect(
        CalendarEventScope.eventTypeForDepartment(Department.studio),
        'room_booking',
      );
    });

    test('non-Studio departments keep the default type (null)', () {
      for (final dept in const [
        Department.marketing,
        Department.montage,
        Department.production,
        Department.sales,
      ]) {
        expect(CalendarEventScope.eventTypeForDepartment(dept), isNull);
      }
    });

    test('no department (company-wide) keeps the default type (null)', () {
      expect(CalendarEventScope.eventTypeForDepartment(null), isNull);
    });
  });

  group('CalendarEventScope.isBookingDepartment', () {
    test('only Studio is a booking department', () {
      expect(CalendarEventScope.isBookingDepartment(Department.studio), isTrue);
      expect(CalendarEventScope.isBookingDepartment(Department.sales), isFalse);
      expect(CalendarEventScope.isBookingDepartment(null), isFalse);
    });
  });
}
