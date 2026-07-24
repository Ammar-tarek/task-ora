// lib/features/super_admin/reset_app_dialog.dart
// Confirmation dialog with password re-verification for resetting app data.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/reset_app_repository.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';

class ResetAppDialog extends StatefulWidget {
  const ResetAppDialog({super.key});

  @override
  State<ResetAppDialog> createState() => _ResetAppDialogState();
}

class _ResetAppDialogState extends State<ResetAppDialog> {
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _resetting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    final password = _passCtrl.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMsg = 'Please enter your password to confirm');
      return;
    }

    setState(() {
      _resetting = true;
      _errorMsg = null;
    });

    final authNotifier = context.read<AuthNotifier>();
    final profile = authNotifier.profile;
    final email = SupabaseService.auth.currentUser?.email;

    if (profile == null || email == null) {
      setState(() {
        _resetting = false;
        _errorMsg = 'Authentication session lost. Please re-login.';
      });
      return;
    }

    // 1. Re-verify password with Supabase Auth
    try {
      final res = await SupabaseService.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        setState(() {
          _resetting = false;
          _errorMsg = 'Password confirmation failed.';
        });
        return;
      }
    } catch (_) {
      setState(() {
        _resetting = false;
        _errorMsg = 'Incorrect password. Data reset cancelled.';
      });
      return;
    }

    // 2. Perform Application Data Reset (spares only Super Admin profile)
    final err = await ResetAppRepository.resetApplicationData(
      superAdminId: profile.id,
    );

    if (!mounted) return;
    setState(() => _resetting = false);

    if (err != null) {
      setState(() => _errorMsg = 'Reset failed: $err');
    } else {
      Navigator.of(context).pop(true); // Return true indicating success
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application data has been successfully reset!'),
          backgroundColor: AppColors.statusDone,
        ),
      );
      // Refresh current auth profile state
      authNotifier.refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Reset Application Data',
            style: AppTextStyles.headlineSm.copyWith(color: AppColors.error),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WARNING: This action is irreversible. All tasks, attendance, finance, expenses, events, rooms, teams, notes, and non-super-admin user records will be permanently purged.',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your Super Admin account will remain intact.',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.gold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_errorMsg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMsg!,
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                ),
              ),
              const SizedBox(height: 14),
            ],

            Text(
              'Enter your Super Admin Password to confirm:',
              style: AppTextStyles.labelMd,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resetting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _resetting ? null : _handleReset,
          child: _resetting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm Data Reset'),
        ),
      ],
    );
  }
}
