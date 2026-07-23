// lib/core/repositories/notification_repository.dart

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
  static final _admin = SupabaseService.adminClient;

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

  // ── Admin: ALL notifications ───────────────────────────────────────────────

  static Future<List<AppNotification>> fetchAll() async {
    try {
      final data = await _admin
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return (data as List).map((m) => AppNotification.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Manager: own + team employees' notifications ───────────────────────────

  static Future<List<AppNotification>> fetchForTeam(String teamId) async {
    try {
      // 1) Get all member IDs in this team
      final members = await _admin
          .from('profiles')
          .select('id')
          .eq('team_id', teamId);
      final ids = (members as List).map((m) => m['id'] as String).toList();
      if (ids.isEmpty) return [];

      // 2) Fetch notifications for all team members
      final data = await _admin
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
      await _admin
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
      await _admin
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
        await _admin
            .from('notifications')
            .update({'is_read': true, 'read_at': now})
            .eq('is_read', false);
      } else if (profile != null &&
          profile.isManager == true &&
          profile.teamId != null) {
        final members = await _admin
            .from('profiles')
            .select('id')
            .eq('team_id', profile.teamId!);
        final ids = (members as List).map((m) => m['id'] as String).toList();
        if (!ids.contains(profile.id)) ids.add(profile.id);
        if (ids.isNotEmpty) {
          await _admin
              .from('notifications')
              .update({'is_read': true, 'read_at': now})
              .inFilter('recipient_id', ids)
              .eq('is_read', false);
        }
      } else if (profile != null) {
        await _admin
            .from('notifications')
            .update({'is_read': true, 'read_at': now})
            .eq('recipient_id', profile.id)
            .eq('is_read', false);
      }
    } catch (_) {}
  }

  static Future<void> createNotification({
    required String recipientId,
    required String type,
    required String title,
    required String body,
    String? referenceType,
    String? referenceId,
  }) async {
    try {
      await _admin.from('notifications').insert({
        'recipient_id': recipientId,
        'type': type,
        'title': title,
        'body': body,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'is_read': false,
        'channel': 'in_app',
      });
    } catch (_) {}
  }

  /// Subscribe to new notifications in real-time.
  /// Returns a stream of raw notification maps.
  /// Returns an empty stream if the table doesn't exist.
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
