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
import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  RealtimeService.instance.init(); // live auto-refresh across the app
  await LocalNotificationService.init(); // device push-notification setup

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
    // Start WiFi attendance tracking for employees AND managers.
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
    // Rebuild whenever the theme mode changes so the palette swap takes effect.
    context.watch<ThemeController>();
    final localeCtrl = context.watch<LocaleController>();

    return MaterialApp.router(
      title: 'CB TO-DO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: widget.router,
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
