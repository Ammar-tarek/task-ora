// lib/core/repositories/notification_repository.dart

import '../services/supabase_service.dart';

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? referenceType;
  final String? referenceId;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.referenceType,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id:            m['id'] as String,
    type:          m['type'] as String? ?? '',
    title:         m['title'] as String? ?? '',
    body:          m['body'] as String? ?? '',
    referenceType: m['reference_type'] as String?,
    referenceId:   m['reference_id'] as String?,
    isRead:        m['is_read'] as bool? ?? false,
    createdAt:     m['created_at'] as String? ?? '',
  );
}

class NotificationRepository {
  static final _client = SupabaseService.client;

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

  static Future<void> markRead(String notificationId) async {
    try {
      await _client.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('id', notificationId);
    } catch (_) { /* table may not exist yet */ }
  }

  static Future<void> markAllRead(String userId) async {
    try {
      await _client.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('recipient_id', userId).eq('is_read', false);
    } catch (_) { /* table may not exist yet */ }
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
