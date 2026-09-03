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

  /// The single super admin. DB `user_role` has no 'super_admin' value, so we
  /// identify them by email via the service-role auth admin API and cache the
  /// resolved profile id. They ALWAYS receive every notification.
  static const _superAdminEmail = 'ammar@cashback.com';
  static String? _cachedSuperAdminId;
  static bool _superAdminResolved = false;

  static Future<String?> _superAdminId() async {
    if (_superAdminResolved) return _cachedSuperAdminId;
    try {
      final users = await _admin.auth.admin.listUsers();
      for (final u in users) {
        if ((u.email ?? '').toLowerCase() == _superAdminEmail) {
          _cachedSuperAdminId = u.id;
          break;
        }
      }
    } catch (_) {}
    _superAdminResolved = true;
    return _cachedSuperAdminId;
  }

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

  /// Broadcast a notification for any system/task action to:
  /// 1. Target assigned employees / users ([targetUserIds])
  /// 2. Team Manager / Team Lead of the team ([teamId])
  /// 3. ALL Admins and Super Admins
  /// Excludes [actorId] so the performing user does not receive their own action alert.
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
      final recipients = <String>{};

      // 1) Target Users / Assignees
      if (targetUserIds != null) {
        recipients.addAll(targetUserIds.where((id) => id.isNotEmpty));
      }

      // 2) Team Lead + ALL managers of the team (the employee's/department's
      //    manager must always be notified for that team's events).
      if (teamId != null && teamId.isNotEmpty) {
        try {
          final teamData = await _admin
              .from('teams')
              .select('team_lead_id')
              .eq('id', teamId)
              .maybeSingle();
          if (teamData != null && teamData['team_lead_id'] != null) {
            recipients.add(teamData['team_lead_id'] as String);
          }
        } catch (_) {}
        try {
          final managerRows = await _admin
              .from('profiles')
              .select('id')
              .eq('team_id', teamId)
              .eq('role', 'manager');
          for (final r in (managerRows as List)) {
            final id = r['id'] as String?;
            if (id != null && id.isNotEmpty) recipients.add(id);
          }
        } catch (_) {}
      }

      // 3) ALL Admins (DB user_role has no 'super_admin' value — filtering on
      //    it would 400; admins are the top DB role).
      final superAdminIds = <String>{};
      try {
        final adminRows = await _admin
            .from('profiles')
            .select('id, role')
            .eq('role', 'admin');
        for (final r in (adminRows as List)) {
          final id = r['id'] as String?;
          final role = r['role'] as String? ?? '';
          if (id != null && id.isNotEmpty) {
            recipients.add(id);
            if (role == 'super_admin') {
              superAdminIds.add(id);
            }
          }
        }
      } catch (_) {
        try {
          final allProfiles = await _admin.from('profiles').select('id, role');
          for (final r in (allProfiles as List)) {
            final role = r['role'] as String? ?? '';
            final id = r['id'] as String?;
            if (id != null && (role == 'admin' || role == 'super_admin')) {
              recipients.add(id);
              if (role == 'super_admin') {
                superAdminIds.add(id);
              }
            }
          }
        } catch (_) {}
      }

      // 3b) The super admin (ammar@cashback.com) ALWAYS receives every
      //     notification and is retained even when they are the actor.
      final superId = await _superAdminId();
      if (superId != null && superId.isNotEmpty) {
        recipients.add(superId);
        superAdminIds.add(superId);
      }

      // 4) Remove actorId for standard users/managers UNLESS explicitly targeted
      //    in targetUserIds (the super admin is always retained).
      if (actorId != null && actorId.isNotEmpty) {
        final explicitlyTargeted = targetUserIds?.contains(actorId) ?? false;
        if (!explicitlyTargeted) {
          recipients.removeWhere((id) => id == actorId && !superAdminIds.contains(id));
        }
      }

      if (recipients.isEmpty) return;

      // 5) Insert rows into notifications table
      final inserts = recipients.map((rId) => {
        'recipient_id': rId,
        'type': type,
        'title': title,
        'body': body,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'is_read': false,
        'channel': 'in_app',
      }).toList();

      await _admin.from('notifications').insert(inserts);
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
