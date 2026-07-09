// lib/core/services/local_notification_service.dart
// Thin wrapper around flutter_local_notifications.
// Call LocalNotificationService.init() once in main(), then use
// LocalNotificationService.show() anywhere in the app.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ── Notification channel IDs ──────────────────────────────────────────────

  static const _channelTaskId   = 'taskora_tasks';
  static const _channelTaskName = 'Tasks';

  static const _channelHrId   = 'taskora_hr';
  static const _channelHrName = 'HR & Attendance';

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Call once in main() before runApp().
  static Future<void> init() async {
    if (_initialized) return;
    // Local notifications are mobile-only — skip entirely on web/desktop.
    if (kIsWeb) { _initialized = true; return; }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Create notification channels (Android 8+) and request permission (Android 13+).
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelTaskId,
            _channelTaskName,
            description: 'Task assignments, status changes and handoffs',
            importance: Importance.high,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelHrId,
            _channelHrName,
            description: 'Attendance check-in/out and penalty alerts',
            importance: Importance.high,
          ),
        );
        // Request POST_NOTIFICATIONS permission (Android 13+).
        await androidPlugin.requestNotificationsPermission();
      }
    }

    _initialized = true;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Pass one of these types to [show] to pick the right channel.
  static const String typeTask = 'task';
  static const String typeHr   = 'hr';

  /// Show a local notification immediately.
  ///
  /// [type]  — use [typeTask] or [typeHr].
  /// [id]    — optional stable id; collisions replace the previous notif.
  static Future<void> show({
    required String title,
    required String body,
    String type = typeTask,
    int?   id,
  }) async {
    if (!_initialized || kIsWeb) return;

    final channelId   = type == typeHr ? _channelHrId   : _channelTaskId;
    final channelName = type == typeHr ? _channelHrName : _channelTaskName;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority:   Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );

    final notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id ?? DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notifDetails,
    );
  }
}
