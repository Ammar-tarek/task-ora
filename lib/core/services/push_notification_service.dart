// lib/core/services/push_notification_service.dart
// Handles Firebase Cloud Messaging (FCM) initialization, background handlers,
// FCM token registration with Supabase profiles table, and local push triggers.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/profile_model.dart';
import '../repositories/profile_repository.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized when handling background/terminated messages
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static bool _initialized = false;
  String? _currentUserId;

  /// Call once in `main()` before `runApp()`.
  static Future<void> init() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      }

      final messaging = FirebaseMessaging.instance;

      // Request alert / sound permissions for FCM push on iOS & Android 13+ & Web
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (!kIsWeb) {
        // Set foreground notification options (show alert even when app is open)
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // ── Foreground Message Listener ──────────────────────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final title = notification?.title ?? message.data['title'] ?? 'CashBack Alert';
        final body = notification?.body ?? message.data['body'] ?? '';
        final type = message.data['type'] ?? 'task';
        final refType = message.data['reference_type'];
        final refId = message.data['reference_id'];

        LocalNotificationService.show(
          title: title,
          body: body,
          type: type == 'hr' ? LocalNotificationService.typeHr : LocalNotificationService.typeTask,
          payload: (refType != null && refId != null) ? '$refType:$refId' : 'notifications',
        );
      });

      // ── Notification Click (App opened from background) ─────────────────
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        LocalNotificationService.show(
          title: message.notification?.title ?? 'Notification',
          body: message.notification?.body ?? '',
        );
      });

      _initialized = true;
    } catch (_) {
      // Firebase setup failed or missing configuration — gracefully fall back
    }
  }

  /// Call after user signs in to register & sync their FCM Token to Supabase.
  void start(ProfileModel profile) async {
    _currentUserId = profile.id;
    if (!_initialized) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Fetch and update token
      final token = await messaging.getToken();
      if (token != null) {
        await ProfileRepository.updateFcmToken(profile.id, token);
      }

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) async {
        if (_currentUserId != null) {
          await ProfileRepository.updateFcmToken(_currentUserId!, newToken);
        }
      });
    } catch (_) {}
  }

  /// Call when the user signs out.
  void stop() async {
    if (_currentUserId != null) {
      await ProfileRepository.updateFcmToken(_currentUserId!, null);
      _currentUserId = null;
    }
  }
}
