// lib/core/services/push_notification_service.dart
// Handles Firebase Cloud Messaging (FCM) initialization across Web, Android, and iOS,
// background message handlers, FCM token registration with Supabase profiles table,
// and notification triggers.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../firebase_options.dart';
import '../models/profile_model.dart';
import '../repositories/profile_repository.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized when handling background/terminated messages
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static bool _initialized = false;
  String? _currentUserId;

  /// Call once during app startup.
  static Future<void> init() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final isSupported =
          kIsWeb ? await FirebaseMessaging.instance.isSupported() : true;
      if (!isSupported) {
        debugPrint('[FCM] Web Push is not supported in this browser environment.');
        return;
      }

      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      }

      final messaging = FirebaseMessaging.instance;

      // Request permissions (alert, badge, sound)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      if (!kIsWeb) {
        // Set foreground notification options for native platforms
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // ── Foreground Message Listener ──────────────────────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final title =
            notification?.title ?? message.data['title'] ?? 'CashBack Alert';
        final body = notification?.body ?? message.data['body'] ?? '';
        final type = message.data['type'] ?? 'task';
        final refType = message.data['reference_type'];
        final refId = message.data['reference_id'];

        LocalNotificationService.show(
          title: title,
          body: body,
          type: type == 'hr'
              ? LocalNotificationService.typeHr
              : LocalNotificationService.typeTask,
          payload: (refType != null && refId != null)
              ? '$refType:$refId'
              : 'notifications',
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
    } catch (e) {
      debugPrint('[FCM] Initialization error or missing platform config: $e');
    }
  }

  /// Explicitly check or request notification permissions via FCM.
  Future<NotificationSettings?> requestNotificationPermission() async {
    try {
      if (!_initialized) await init();
      final isSupported =
          kIsWeb ? await FirebaseMessaging.instance.isSupported() : true;
      if (!isSupported) return null;

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (_currentUserId != null &&
          (settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional)) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await ProfileRepository.updateFcmToken(_currentUserId!, token);
        }
      }

      return settings;
    } catch (e) {
      debugPrint('[FCM] Error requesting notification permission: $e');
      return null;
    }
  }

  /// Call after user signs in to register & sync their FCM Token to Supabase.
  void start(ProfileModel profile) async {
    _currentUserId = profile.id;

    try {
      if (!_initialized) await init();

      final isSupported =
          kIsWeb ? await FirebaseMessaging.instance.isSupported() : true;
      if (!isSupported) return;

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
    } catch (e) {
      debugPrint('[FCM] Error syncing FCM token for user ${profile.id}: $e');
    }
  }

  /// Call when the user signs out.
  void stop() async {
    if (_currentUserId != null) {
      try {
        await ProfileRepository.updateFcmToken(_currentUserId!, null);
      } catch (_) {}
      _currentUserId = null;
    }
  }
}
