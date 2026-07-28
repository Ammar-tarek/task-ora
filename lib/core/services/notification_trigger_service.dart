// lib/core/services/notification_trigger_service.dart
// Single source of truth for device notifications: subscribes to the
// `notifications` table (rows are created by DB triggers) filtered to the
// current user, and shows a local device notification for each new row.
//
// Because the server (DB triggers) decides the recipients, this covers every
// notification type automatically — no per-event logic needed here.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../services/supabase_service.dart';
import 'local_notification_service.dart';

class NotificationTriggerService {
  NotificationTriggerService._();
  static final NotificationTriggerService instance =
      NotificationTriggerService._();

  RealtimeChannel? _channel;
  ProfileModel? _profile;

  // Deduplication set to guarantee that duplicate Realtime event dispatches
  // or reconnects never trigger duplicate mobile notifications.
  final Set<String> _processedIds = <String>{};

  // HR / Financial / System types go to the HR channel; everything else to Tasks.
  static const _hrTypes = {
    'attendance_alert',
    'attendance_checkin',
    'attendance_checkout',
    'attendance_approved',
    'penalty_applied',
    'penalty_created',
    'penalty_updated',
    'expense_created',
    'expense_approved',
    'expense_rejected',
    'role_changed',
    'team_changed',
    'announcement_created',
  };

  /// Call after the user signs in (profile is available).
  void start(ProfileModel profile) {
    if (_profile?.id == profile.id && _channel != null) return;
    _profile = profile;
    _stop();

    _channel =
        SupabaseService.client
            .channel('public:notifications:recipient_id=eq.${profile.id}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'recipient_id',
                value: profile.id,
              ),
              callback: (payload) {
                final row = payload.newRecord;
                final recipientId = row['recipient_id'] as String?;
                if (recipientId != null && recipientId != profile.id) return;

                final notifId = row['id'] as String?;
                if (notifId != null) {
                  if (_processedIds.contains(notifId)) return;
                  _processedIds.add(notifId);
                  if (_processedIds.length > 200) {
                    _processedIds.remove(_processedIds.first);
                  }
                }

                final type = row['type'] as String? ?? 'system';
                final refType = row['reference_type'] as String?;
                final refId = row['reference_id'] as String?;
                final title = row['title'] as String? ?? 'CashBack Notification';
                final body = row['body'] as String? ?? '';

                final intId = notifId != null
                    ? (notifId.hashCode.abs() % 100000)
                    : (DateTime.now().millisecondsSinceEpoch % 100000);

                LocalNotificationService.show(
                  id: intId,
                  title: title,
                  body: body,
                  type: _hrTypes.contains(type)
                      ? LocalNotificationService.typeHr
                      : LocalNotificationService.typeTask,
                  payload: (refType != null && refId != null)
                      ? '$refType:$refId'
                      : 'notifications',
                );
              },
            )
          ..subscribe();
  }

  /// Call when the user signs out.
  void stop() => _stop();

  void _stop() {
    if (_channel != null) {
      SupabaseService.adminClient.removeChannel(_channel!);
      _channel = null;
    }
    _processedIds.clear();
    _profile = null;
  }
}
