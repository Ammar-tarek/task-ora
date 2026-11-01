// lib/core/widgets/department_gate_screen.dart
// Holding screen shown while a user's department is being resolved (or after a
// lookup failure). It exists so the router can FAIL CLOSED: a manager/employee
// whose department is not yet known is parked here — never dropped into the full
// workspace. On success the AuthNotifier notifies and the router moves them on.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_notifier.dart';
import '../theme/app_theme.dart';

class DepartmentGateScreen extends StatelessWidget {
  const DepartmentGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final failed = auth.departmentResolveFailed;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!failed) ...[
                const CircularProgressIndicator(color: AppColors.gold),
                const SizedBox(height: 20),
                Text('Preparing your workspace…',
                    style: AppTextStyles.labelMd, textAlign: TextAlign.center),
              ] else ...[
                Icon(Icons.wifi_off_outlined,
                    size: 56, color: AppColors.outlineVariant),
                const SizedBox(height: 16),
                Text('Couldn’t load your workspace',
                    style: AppTextStyles.headlineSm, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'We could not confirm your department. Check your connection '
                  'and try again.',
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => auth.retryDepartmentResolution(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
