// lib/core/services/local_notification_service.dart
// Thin wrapper around flutter_local_notifications & web notifications.
// Call LocalNotificationService.init() once in main(), then use
// LocalNotificationService.show() anywhere in the app.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'web_notification/web_notification.dart';

class NotificationAlertPayload {
  final String title;
  final String body;
  final String? payload;
  const NotificationAlertPayload({
    required this.title,
    required this.body,
    this.payload,
  });
}

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Router reference for navigating when a push notification is tapped.
  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  /// Stream of in-app notification alerts for active UI banner overlays.
  static final _alertController =
      StreamController<NotificationAlertPayload>.broadcast();
  static Stream<NotificationAlertPayload> get onNotificationAlert =>
      _alertController.stream;

  // ── Notification channel IDs ──────────────────────────────────────────────

  static const _channelTaskId = 'cbtodo_tasks';
  static const _channelTaskName = 'Tasks';

  static const _channelHrId = 'cbtodo_hr';
  static const _channelHrName = 'HR & Attendance';

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Call once in main() before runApp().
  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      requestWebNotificationPermission();
      _initialized = true;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels (Android 8+) and request permission (Android 13+).
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
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

  // ── Tap handler ──────────────────────────────────────────────────────────

  static void _onNotificationTap(NotificationResponse response) {
    if (_router == null) return;
    _router!.push('/notifications');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static const String typeTask = 'task';
  static const String typeHr = 'hr';

  /// Show a local notification immediately & emit in-app banner alert.
  static Future<void> show({
    required String title,
    required String body,
    String type = typeTask,
    int? id,
    String? payload,
  }) async {
    // Always broadcast in-app alert payload for active UI screens
    _alertController.add(
      NotificationAlertPayload(title: title, body: body, payload: payload),
    );

    if (!_initialized) return;
    if (kIsWeb) {
      showWebNotification(title: title, body: body);
      return;
    }

    final channelId = type == typeHr ? _channelHrId : _channelTaskId;
    final channelName = type == typeHr ? _channelHrName : _channelTaskName;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
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
      id: id ?? (DateTime.now().millisecondsSinceEpoch % 100000),
      title: title,
      body: body,
      notificationDetails: notifDetails,
      payload: payload,
    );
  }
}
