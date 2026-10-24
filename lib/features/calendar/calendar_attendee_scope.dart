// lib/features/calendar/calendar_attendee_scope.dart
// Pure rules for department-scoped calendar events + attendees, so the logic is
// unit-testable without Flutter/Supabase. RLS remains the real boundary.

class CalendarAttendeeScope {
  CalendarAttendeeScope._();

  /// The team that OWNS a newly created event.
  ///  - admin: the ACTIVE workspace department team ([activeDeptTeamId]); null
  ///    means "All Departments" → caller must block creation (no orphan event).
  ///  - everyone else: their own verified team ([profileTeamId]).
  /// A scoped (non-admin) user can never choose another team.
  static String? ownerTeamId({
    required bool isAdmin,
    required String? activeDeptTeamId,
    required String? profileTeamId,
  }) =>
      isAdmin ? activeDeptTeamId : profileTeamId;

  /// Keep only the selected attendee ids that are still eligible (members of the
  /// event's department). Used to clear stale selections when the team changes.
  static Set<String> keepEligible(
    Set<String> selected,
    Iterable<String> eligibleIds,
  ) {
    final eligible = eligibleIds.toSet();
    return selected.where(eligible.contains).toSet();
  }

  /// True when [attendeeTeamId] may be an attendee of an event owned by
  /// [eventTeamId]. Cross-department attendees and unassigned events are
  /// rejected (mirrors the proposed DB trigger).
  static bool attendeeAllowed({
    required String? eventTeamId,
    required String? attendeeTeamId,
  }) =>
      eventTeamId != null && attendeeTeamId == eventTeamId;
}
