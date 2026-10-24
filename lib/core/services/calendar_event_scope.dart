// lib/core/services/calendar_event_scope.dart
// Pure rules for department-aware calendar event creation.
//
// Kept side-effect free (mirrors TaskCreateScope) so it is unit-testable and
// reused by the New Event form. The database remains the real boundary: the
// RLS policies decide visibility/authority, and the `events_studio_booking_no_overlap`
// exclusion constraint — not this code — actually prevents overlapping bookings.

import '../constants/departments.dart';

class CalendarEventScope {
  CalendarEventScope._();

  /// The `events.event_type` a newly created event must carry for its owning
  /// [department]:
  ///   • Studio  → 'room_booking', so the Studio-only overlap exclusion
  ///               constraint protects the studio slot (and the time range is
  ///               validated as start < end);
  ///   • anything else (or null) → null, i.e. keep the column default ('other').
  static String? eventTypeForDepartment(Department? department) =>
      department == Department.studio ? 'room_booking' : null;

  /// Whether events owned by [department] are time-sensitive room bookings.
  static bool isBookingDepartment(Department? department) =>
      department == Department.studio;
}
