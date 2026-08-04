// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/services/supabase_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/wifi_attendance_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/notification_trigger_service.dart';
import 'core/services/apk_update_service.dart';
import 'core/auth/auth_notifier.dart';
import 'core/providers/locale_controller.dart';
import 'core/providers/team_filter_notifier.dart';
import 'core/providers/team_privileges_notifier.dart';
import 'core/providers/theme_controller.dart';
import 'core/services/push_notification_service.dart';
import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar', null);
  await SupabaseService.initialize();
  RealtimeService.instance.init(); // live auto-refresh across the app
  await LocalNotificationService.init(); // device push-notification setup
  await PushNotificationService.init(); // FCM push notification setup

  final auth = AuthNotifier();
  final teamPrivs = TeamPrivilegesNotifier(auth);

  // Create the router exactly once — must live outside the widget tree
  // to avoid duplicate-navigator-key assertions on rebuilds.
  final router = makeRouter(auth);
  LocalNotificationService.setRouter(router);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => TeamFilterNotifier()),
        ChangeNotifierProvider.value(value: teamPrivs),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => LocaleController()),
      ],
      child: CbToDoApp(router: router),
    ),
  );
}

class CbToDoApp extends StatefulWidget {
  const CbToDoApp({super.key, required this.router});
  final GoRouter router;
  @override
  State<CbToDoApp> createState() => _CbToDoAppState();
}

class _CbToDoAppState extends State<CbToDoApp> with WidgetsBindingObserver {
  AuthNotifier? _auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAuth = Provider.of<AuthNotifier>(context, listen: false);
    if (_auth != newAuth) {
      _auth?.removeListener(_onAuthChanged);
      _auth = newAuth;
      _auth?.addListener(_onAuthChanged);
      _onAuthChanged();
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;

    final profile = auth.profile;
    // Start WiFi attendance tracking for logged in users (employees, managers, admins, super admins).
    if (auth.isLoggedIn && profile != null) {
      WifiAttendanceService.instance.init(profile.id);
    } else {
      WifiAttendanceService.instance.dispose();
    }

    // Start / stop realtime notification triggers & FCM push based on login state & check updates.
    if (auth.isLoggedIn && profile != null) {
      NotificationTriggerService.instance.start(profile);
      PushNotificationService.instance.start(profile);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !kIsWeb) ApkUpdateService.checkForUpdates(context);
      });
    } else {
      NotificationTriggerService.instance.stop();
      PushNotificationService.instance.stop();
    }
  }

  // Re-check WiFi whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final profile = context.read<AuthNotifier>().profile;
      if (profile != null) {
        WifiAttendanceService.instance.checkNow();
        if (!kIsWeb) ApkUpdateService.checkForUpdates(context);
      }
      // Refresh privileges so admin/manager edits take effect on next foreground.
      context.read<TeamPrivilegesNotifier>().reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the theme mode changes so the palette swap takes effect.
    final themeCtrl = context.watch<ThemeController>();
    final localeCtrl = context.watch<LocaleController>();

    return MaterialApp.router(
      title: 'CashBack',
      debugShowCheckedModeBanner: false,
      locale: localeCtrl.locale,
      theme: AppTheme.build(),
      darkTheme: AppTheme.build(),
      themeMode: themeCtrl.isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: widget.router,
      scrollBehavior: const AppScrollBehavior(),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
