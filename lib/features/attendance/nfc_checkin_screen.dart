// lib/features/attendance/nfc_checkin_screen.dart
//
// NFC / deep-link attendance check-in landing screen.
//
// The single physical NFC sticker holds ONE shared HTTPS URL:
//     https://<production-domain>/checkin
//
// The sticker never contains a user id, email, token or any identity data.
// When an employee taps the sticker:
//   • Android App Link / iOS Universal Link opens the Flutter app on `/checkin`
//     (or, if the app is not installed, the mobile web build opens the same
//     route in the browser).
//   • The employee identity is taken ONLY from the already-authenticated
//     Supabase session (JWT) — never from the URL.
//   • The check-in is created for that authenticated employee and the existing
//     duplicate-prevention rules in AttendanceRepository.checkIn apply.
//
// Unauthenticated users are sent to /login by the router guard and returned
// here automatically after a successful sign-in.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/attendance_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';
import 'package:intl/intl.dart';

enum _CheckInState { working, success, alreadyIn, error, blocked }

class NfcCheckInScreen extends StatefulWidget {
  const NfcCheckInScreen({super.key});

  @override
  State<NfcCheckInScreen> createState() => _NfcCheckInScreenState();
}

class _NfcCheckInScreenState extends State<NfcCheckInScreen> {
  _CheckInState _state = _CheckInState.working;
  String? _message;
  String? _checkInTime; // formatted Egypt wall-clock time

  @override
  void initState() {
    super.initState();
    // Attempt the check-in automatically once the first frame is up so the
    // AuthNotifier / profile are available from Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheckIn());
  }

  Future<void> _runCheckIn() async {
    if (!mounted) return;
    setState(() {
      _state = _CheckInState.working;
      _message = null;
    });

    final profile = context.read<AuthNotifier>().profile;

    // Identity comes exclusively from the authenticated session/profile.
    if (profile == null) {
      // Router guard normally prevents reaching here unauthenticated; guard
      // anyway so we never create attendance without an identity.
      setState(() {
        _state = _CheckInState.error;
        _message = 'You are not signed in. Please sign in and try again.';
      });
      return;
    }

    // Clients are not staff — they must not create attendance records.
    if (profile.isClient) {
      setState(() {
        _state = _CheckInState.blocked;
        _message = 'Attendance check-in is only available to employees.';
      });
      return;
    }

    // Was the employee already checked in today (before this tap)?
    final before = await AttendanceRepository.fetchTodayForEmployee(profile.id);
    final wasCheckedIn = before?.isCheckedIn == true;

    final err = await AttendanceRepository.checkIn(profile.id);
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _state = _CheckInState.error;
        _message = err;
      });
      return;
    }

    // Reload to show the recorded check-in time.
    final after = await AttendanceRepository.fetchTodayForEmployee(profile.id);
    if (!mounted) return;
    String? timeStr;
    final inIso = after?.checkInTime;
    if (inIso != null) {
      try {
        timeStr = DateFormat('hh:mm a').format(AppTime.cairo(DateTime.parse(inIso)));
      } catch (_) {}
    }

    setState(() {
      _checkInTime = timeStr;
      _state = wasCheckedIn ? _CheckInState.alreadyIn : _CheckInState.success;
    });
  }

  void _goToApp() {
    final profile = context.read<AuthNotifier>().profile;
    final role = profile?.role ?? 'employee';
    final home = (role == 'admin' || role == 'super_admin' || role == 'manager')
        ? '/dashboard'
        : '/tasks';
    context.go(home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CheckInState.working:
        return const _CenterColumn(
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 20),
            Text('Recording your attendance…'),
          ],
        );

      case _CheckInState.success:
      case _CheckInState.alreadyIn:
        final already = _state == _CheckInState.alreadyIn;
        return _CenterColumn(
          children: [
            Icon(
              already ? Icons.verified_outlined : Icons.check_circle_outline,
              color: AppColors.statusDone,
              size: 88,
            ),
            const SizedBox(height: 16),
            Text(
              already ? 'Already Checked In' : 'Checked In',
              style: AppTextStyles.headlineSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _checkInTime != null
                  ? 'Check-in time: $_checkInTime'
                  : (already
                      ? 'Your attendance for today was already recorded.'
                      : 'Your attendance has been recorded for today.'),
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _goToApp,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to app'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.gold,
                ),
              ),
            ),
          ],
        );

      case _CheckInState.blocked:
        return _CenterColumn(
          children: [
            const Icon(Icons.block_outlined,
                color: AppColors.statusHigh, size: 88),
            const SizedBox(height: 16),
            Text(_message ?? 'Not available.',
                style: AppTextStyles.bodyMd, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _goToApp,
                child: const Text('Continue to app'),
              ),
            ),
          ],
        );

      case _CheckInState.error:
        return _CenterColumn(
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.error, size: 88),
            const SizedBox(height: 16),
            Text('Check-in failed',
                style: AppTextStyles.headlineSm, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _message ?? 'Something went wrong. Please try again.',
              style: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _runCheckIn,
                icon: const Icon(Icons.login_outlined),
                label: const Text('Check In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusDone,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _goToApp,
                child: const Text('Continue to app'),
              ),
            ),
          ],
        );
    }
  }
}

class _CenterColumn extends StatelessWidget {
  const _CenterColumn({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
}
