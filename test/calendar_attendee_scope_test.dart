// test/calendar_attendee_scope_test.dart
// Department-scoped calendar event + attendee rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/features/calendar/calendar_attendee_scope.dart';

void main() {
  group('CalendarAttendeeScope.ownerTeamId', () {
    test('admin uses the active workspace department team', () {
      expect(
        CalendarAttendeeScope.ownerTeamId(
          isAdmin: true,
          activeDeptTeamId: 'marketing',
          profileTeamId: 'ignored',
        ),
        'marketing',
      );
    });

    test('admin in All Departments → null (caller must block creation)', () {
      expect(
        CalendarAttendeeScope.ownerTeamId(
          isAdmin: true,
          activeDeptTeamId: null,
          profileTeamId: 'ignored',
        ),
        isNull,
      );
    });

    test('non-admin is bound to their own team, never the workspace', () {
      expect(
        CalendarAttendeeScope.ownerTeamId(
          isAdmin: false,
          activeDeptTeamId: 'studio',
          profileTeamId: 'montage',
        ),
        'montage',
      );
    });
  });

  group('CalendarAttendeeScope.keepEligible (clear stale on switch)', () {
    test('drops selected ids not in the new eligible set', () {
      final kept = CalendarAttendeeScope.keepEligible(
        {'a', 'b', 'c'},
        ['b', 'c', 'd'],
      );
      expect(kept, {'b', 'c'});
    });

    test('empty eligible set clears everything', () {
      expect(CalendarAttendeeScope.keepEligible({'a', 'b'}, const []), isEmpty);
    });
  });

  group('CalendarAttendeeScope.attendeeAllowed (cross-dept rejection)', () {
    test('same department is allowed', () {
      expect(
        CalendarAttendeeScope.attendeeAllowed(
          eventTeamId: 'marketing',
          attendeeTeamId: 'marketing',
        ),
        isTrue,
      );
    });

    test('other department is rejected', () {
      expect(
        CalendarAttendeeScope.attendeeAllowed(
          eventTeamId: 'marketing',
          attendeeTeamId: 'sales',
        ),
        isFalse,
      );
    });

    test('unassigned event (null team) rejects all attendees', () {
      expect(
        CalendarAttendeeScope.attendeeAllowed(
          eventTeamId: null,
          attendeeTeamId: 'marketing',
        ),
        isFalse,
      );
      expect(
        CalendarAttendeeScope.attendeeAllowed(
          eventTeamId: null,
          attendeeTeamId: null,
        ),
        isFalse,
      );
    });
  });
}
