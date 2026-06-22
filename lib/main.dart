// lib/main.dart
import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:provider/provider.dart';
import 'core/services/supabase_service.dart';
import 'core/services/wifi_attendance_service.dart';
import 'core/auth/auth_notifier.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthNotifier(),
      child: DevicePreview(
        enabled: true,
        builder: (context) => const TaskOraApp(),
      ),
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
      if (profile?.isEmployee == true) {
        WifiAttendanceService.instance.checkNow();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthNotifier>(context);

    // Start / restart WiFi service whenever the logged-in employee changes.
    if (auth.isLoggedIn && auth.profile?.isEmployee == true) {
      WifiAttendanceService.instance.init(auth.profile!.id);
    } else {
      WifiAttendanceService.instance.dispose();
    }

    return MaterialApp.router(
      title: 'TaskOra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: makeRouter(auth),
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
    );
  }
}
