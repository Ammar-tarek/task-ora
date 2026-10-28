// test/notification_route_test.dart
// Verifies notification deep-link routing, especially that calendar/event
// notifications and meeting reminders route to the calendar, and that the
// legacy 'calendar' and standardized 'event' reference types are both honored.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/services/notification_route.dart';

void main() {
  group('notificationRouteFor — reference_type (preferred)', () {
    test('event and reminder reference types route to the calendar', () {
      expect(
        notificationRouteFor(referenceType: 'event', referenceId: 'e1'),
        '/calendar',
      );
      // Legacy value still used by older rows must keep working.
      expect(
        notificationRouteFor(referenceType: 'calendar', referenceId: 'e1'),
        '/calendar',
      );
    });

    test('task routes to its detail when an id is present, else the board', () {
      expect(
        notificationRouteFor(referenceType: 'task', referenceId: 't1'),
        '/tasks/detail/t1',
      );
      expect(notificationRouteFor(referenceType: 'task'), '/tasks');
    });

    test('other explicit reference types route correctly', () {
      expect(notificationRouteFor(referenceType: 'expense'), '/expenses');
      expect(notificationRouteFor(referenceType: 'payment'), '/finance');
      // Attendance/Penalties removed from UI — no in-app target.
      expect(notificationRouteFor(referenceType: 'penalty'), isNull);
      expect(notificationRouteFor(referenceType: 'attendance'), isNull);
    });
  });

  group('notificationRouteFor — type fallback (no reference_type)', () {
    test('calendar_event and meeting_reminder fall back to the calendar', () {
      expect(notificationRouteFor(type: 'calendar_event'), '/calendar');
      expect(notificationRouteFor(type: 'meeting_reminder'), '/calendar');
    });

    test('task type falls back correctly; removed features return null', () {
      expect(
        notificationRouteFor(type: 'task_assigned', referenceId: 't2'),
        '/tasks/detail/t2',
      );
      // Attendance/Penalties removed from UI — no in-app target.
      expect(notificationRouteFor(type: 'penalty_applied'), isNull);
      expect(notificationRouteFor(type: 'attendance_alert'), isNull);
    });
  });

  group('notificationRouteFor — precedence & unknowns', () {
    test('reference_type wins over type', () {
      expect(
        notificationRouteFor(
          referenceType: 'event',
          type: 'task_assigned',
          referenceId: 'x',
        ),
        '/calendar',
      );
    });

    test('unknown/empty returns null (no navigation)', () {
      expect(notificationRouteFor(), isNull);
      expect(notificationRouteFor(referenceType: 'mystery'), isNull);
      expect(notificationRouteFor(type: 'system'), isNull);
    });
  });
}
