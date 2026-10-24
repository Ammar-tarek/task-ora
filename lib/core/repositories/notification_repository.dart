// lib/core/repositories/notification_repository.dart
// All reads/writes run on the authenticated client under RLS:
//   employee → own rows; manager → own team; admin/super admin → all.
// Fan-out and single inserts go through SECURITY DEFINER RPCs (notify_action /
// create_notification) so no service-role key is needed on the client.

import '../services/supabase_service.dart';

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? referenceType;
  final String? referenceId;
  final String recipientId;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.referenceType,
    this.referenceId,
    required this.recipientId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] as String,
    type: m['type'] as String? ?? '',
    title: m['title'] as String? ?? '',
    body: m['body'] as String? ?? '',
    referenceType: m['reference_type'] as String?,
    referenceId: m['reference_id'] as String?,
    recipientId: m['recipient_id'] as String? ?? '',
    isRead: m['is_read'] as bool? ?? false,
    createdAt: m['created_at'] as String? ?? '',
  );
}

class NotificationRepository {
  static final _client = SupabaseService.client;

  // ── Employee: own notifications only ───────────────────────────────────────

  static Future<List<AppNotification>> fetchForUser(String userId) async {
    try {
      final data = await _client
          .from('notifications')
          .select()
          .eq('recipient_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return (data as List).map((m) => AppNotification.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Admin: ALL notifications (RLS: admin_all_notifications) ─────────────────

  static Future<List<AppNotification>> fetchAll() async {
    try {
      final data = await _client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return (data as List).map((m) => AppNotification.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Manager: team members' notifications (RLS: manager_team_notifications) ──

  static Future<List<AppNotification>> fetchForTeam(String teamId) async {
    try {
      final members = await _client
          .from('profiles')
          .select('id')
          .eq('team_id', teamId);
      final ids = (members as List).map((m) => m['id'] as String).toList();
      if (ids.isEmpty) return [];

      final data = await _client
          .from('notifications')
          .select()
          .inFilter('recipient_id', ids)
          .order('created_at', ascending: false)
          .limit(100);
      return (data as List).map((m) => AppNotification.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  static Future<void> markRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);
    } catch (_) {
      /* table may not exist yet */
    }
  }

  static Future<void> markAllRead(String userId) async {
    try {
      await _client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('recipient_id', userId)
          .eq('is_read', false);
    } catch (_) {
      /* table may not exist yet */
    }
  }

  static Future<void> markAllReadForProfile(dynamic profile) async {
    try {
      final now = DateTime.now().toIso8601String();
      if (profile != null && profile.isAdmin == true) {
        // RLS admin_all_notifications permits updating every row.
        await _client
            .from('notifications')
            .update({'is_read': true, 'read_at': now})
            .eq('is_read', false);
      } else if (profile != null &&
          profile.isManager == true &&
          profile.teamId != null) {
        final members = await _client
            .from('profiles')
            .select('id')
            .eq('team_id', profile.teamId!);
        final ids = (members as List).map((m) => m['id'] as String).toList();
        if (!ids.contains(profile.id)) ids.add(profile.id);
        if (ids.isNotEmpty) {
          await _client
              .from('notifications')
              .update({'is_read': true, 'read_at': now})
              .inFilter('recipient_id', ids)
              .eq('is_read', false);
        }
      } else if (profile != null) {
        await _client
            .from('notifications')
            .update({'is_read': true, 'read_at': now})
            .eq('recipient_id', profile.id)
            .eq('is_read', false);
      }
    } catch (_) {}
  }

  /// Insert one notification for a recipient (SECURITY DEFINER RPC validates
  /// the caller is authenticated; no service-role key needed).
  static Future<void> createNotification({
    required String recipientId,
    required String type,
    required String title,
    required String body,
    String? referenceType,
    String? referenceId,
  }) async {
    try {
      await _client.rpc('create_notification', params: {
        'p_recipient_id': recipientId,
        'p_type': type,
        'p_title': title,
        'p_body': body,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
      });
    } catch (_) {}
  }

  /// Broadcast for any system/task action. Recipients are derived server-side
  /// by the notify_action RPC: [targetUserIds] + the [teamId] lead/managers +
  /// all admins/super admins. The acting user (auth.uid()) is excluded unless
  /// explicitly targeted or a super admin. [actorId] is accepted for call-site
  /// compatibility but no longer used (the server identifies the actor).
  static Future<void> notifyAction({
    required String title,
    required String body,
    required String type,
    String? referenceType,
    String? referenceId,
    String? teamId,
    List<String>? targetUserIds,
    String? actorId,
  }) async {
    try {
      await _client.rpc('notify_action', params: {
        'p_title': title,
        'p_body': body,
        'p_type': type,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
        'p_team_id': teamId,
        'p_target_user_ids': targetUserIds,
      });
    } catch (_) {}
  }

  /// Subscribe to new notifications in real-time.
  static Stream<List<Map<String, dynamic>>> streamForUser(String userId) {
    try {
      return _client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
    } catch (_) {
      return const Stream.empty();
    }
  }
}
