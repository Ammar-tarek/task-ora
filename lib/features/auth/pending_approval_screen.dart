// lib/features/auth/pending_approval_screen.dart
// Shown to newly-registered employees who have not yet been assigned to a
// team. They stay here until an admin or manager adds them to a team, at
// which point "Check status" refreshes the profile and the router lets them in.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/theme/app_theme.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    await context.read<AuthNotifier>().refreshProfile();
    if (!mounted) return;
    setState(() => _checking = false);

    // If still pending (no team), let the user know nothing changed yet.
    final profile = context.read<AuthNotifier>().profile;
    if (profile != null && profile.isEmployee && profile.teamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Your account is still pending. Please check back later.'),
        backgroundColor: AppColors.primary,
      ));
    }
    // If a team was assigned, the router's refreshListenable fires and
    // automatically redirects away from /pending.
  }

  Future<void> _signOut() => context.read<AuthNotifier>().signOut();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Icon badge
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_outlined,
                    color: AppColors.gold, size: 48),
              ),
              const SizedBox(height: 28),

              Text('Account Pending',
                  style: AppTextStyles.displayMd, textAlign: TextAlign.center),
              const SizedBox(height: 12),

              Text(
                profile?.fullName.isNotEmpty == true
                    ? 'Welcome, ${profile!.firstName}!'
                    : 'Welcome!',
                style: AppTextStyles.headlineSm
                    .copyWith(color: AppColors.gold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(children: [
                  Icon(Icons.groups_outlined,
                      color: AppColors.onSurfaceVariant, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    'Your account has been created successfully.\n\n'
                    'An administrator or team manager needs to add you to a '
                    'team before you can start using CB TO-DO.\n\n'
                    "You'll get full access as soon as you're assigned.",
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_checking ? 'Checking…' : 'Check status'),
                ),
              ),
              const SizedBox(height: 12),

              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_outlined, size: 18),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.onSurfaceVariant),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
