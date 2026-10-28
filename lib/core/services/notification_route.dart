// lib/core/services/notification_route.dart
// Pure mapping from a notification's reference_type / type to an in-app route.
// Kept side-effect free so it is unit-testable and reused by the notifications
// screen's tap handler.
//
// reference_type standardization: the app historically wrote 'calendar' for
// event notifications while the database triggers (and the new reminder /
// status-change notifications) write 'event'. Both are accepted here and map to
// the calendar, so existing 'calendar' rows AND new 'event' rows deep-link
// correctly — a backward-compatible standardization that needs no data change.

/// Resolves the in-app route for a notification, or null when it has no target.
/// Prefers the explicit [referenceType]; falls back to the notification [type].
String? notificationRouteFor({
  String? referenceType,
  String? type,
  String? referenceId,
}) {
  final refId = referenceId;

  // 1) Explicit routing via reference_type.
  // Attendance and Penalties were removed from the app UI — their notifications
  // no longer have an in-app target, so they fall through and return null (the
  // row stays tappable-to-read but navigates nowhere).
  switch (referenceType) {
    case 'task':
      return refId != null ? '/tasks/detail/$refId' : '/tasks';
    case 'expense':
      return '/expenses';
    case 'payment':
      return '/finance';
    case 'calendar': // legacy event reference type
    case 'event': // standardized event reference type (triggers + reminders)
      return '/calendar';
  }

  // 2) Fallback: derive the route from the notification type.
  switch (type) {
    case 'task_assigned':
    case 'task_done':
    case 'task_handoff':
      return refId != null ? '/tasks/detail/$refId' : '/tasks';
    case 'payment_due':
      return '/finance';
    // 'penalty_*' and 'attendance_alert' intentionally omitted — features
    // removed from the UI, so these return null (no navigation target).
    case 'calendar_event':
    case 'meeting_reminder':
      return '/calendar';
  }

  return null;
}
