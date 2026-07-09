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
  ProfileModel?    _profile;

  // HR-flavoured types go to the HR channel; everything else to Tasks.
  static const _hrTypes = {'attendance_alert', 'penalty_applied'};

  /// Call after the user signs in (profile is available).
  void start(ProfileModel profile) {
    if (_profile?.id == profile.id && _channel != null) return;
    _profile = profile;
    _stop();

    _channel = SupabaseService.adminClient
        .channel('notif-${profile.id}')
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
            final type = row['type'] as String? ?? 'system';
            LocalNotificationService.show(
              title: row['title'] as String? ?? 'TaskOra',
              body:  row['body']  as String? ?? '',
              type:  _hrTypes.contains(type)
                  ? LocalNotificationService.typeHr
                  : LocalNotificationService.typeTask,
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
    _profile = null;
  }
}
