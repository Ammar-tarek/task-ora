// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/services/supabase_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/wifi_attendance_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/notification_trigger_service.dart';
import 'core/auth/auth_notifier.dart';
import 'core/providers/locale_controller.dart';
import 'core/providers/team_filter_notifier.dart';
import 'core/providers/team_privileges_notifier.dart';
import 'core/providers/theme_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  RealtimeService.instance.init(); // live auto-refresh across the app
  await LocalNotificationService.init(); // device push-notification setup

  final auth      = AuthNotifier();
  final teamPrivs = TeamPrivilegesNotifier(auth);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => TeamFilterNotifier()),
        ChangeNotifierProvider.value(value: teamPrivs),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => LocaleController()),
      ],
      child: const TaskOraApp(),
    ),
  );
}

class TaskOraApp extends StatefulWidget {
  const TaskOraApp({super.key});
  @override
  State<TaskOraApp> createState() => _TaskOraAppState();
}

class _TaskOraAppState extends State<TaskOraApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check WiFi whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final profile = context.read<AuthNotifier>().profile;
      // Track attendance for both employees and managers
      if (profile?.isEmployee == true || profile?.isManager == true) {
        WifiAttendanceService.instance.checkNow();
      }
      // Refresh privileges so admin/manager edits take effect on next foreground.
      context.read<TeamPrivilegesNotifier>().reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthNotifier>(context);
    // Rebuild whenever the theme mode changes so the palette swap takes effect.
    context.watch<ThemeController>();
    final localeCtrl = context.watch<LocaleController>();

    // Start WiFi attendance tracking for employees AND managers.
    final profile = auth.profile;
    if (auth.isLoggedIn &&
        (profile?.isEmployee == true || profile?.isManager == true)) {
      WifiAttendanceService.instance.init(profile!.id);
    } else {
      WifiAttendanceService.instance.dispose();
    }

    // Start / stop realtime notification triggers based on login state.
    if (auth.isLoggedIn && profile != null) {
      NotificationTriggerService.instance.start(profile);
    } else {
      NotificationTriggerService.instance.stop();
    }

    return MaterialApp.router(
      title: 'TaskOra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: makeRouter(auth),
      // App language (en/ar) — Arabic gets RTL automatically.
      locale: localeCtrl.locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
