// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/theme/app_theme.dart';

import '../../core/services/biometric_service.dart';
import '../../core/services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _biometricAvailable = false;
  bool _hasStoredCreds = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailable();
  }

  Future<void> _checkBiometricAvailable() async {
    final avail = await BiometricService.instance.isAvailable();
    final hasCreds = await BiometricService.instance.hasCredentials();
    if (mounted) {
      setState(() {
        _biometricAvailable = avail;
        _hasStoredCreds = hasCreds;
      });
    }
  }

  /// Fingerprint login: unlock the biometric-gated credentials stored at the
  /// time the user enabled biometric login, then re-authenticate with them.
  /// (Biometrics can't mint a Supabase session by themselves.)
  Future<void> _biometricLogin() async {
    final auth = context.read<AuthNotifier>();
    final creds = await BiometricService.instance.readCredentials();
    if (creds == null) {
      setState(() => _errorMsg = S.t('biometric_no_session'));
      return;
    }
    // Require a fresh fingerprint/face scan before using the stored credentials.
    final unlocked = await BiometricService.instance.authenticate(
      localizedReason: S.t('biometric_auth_reason'),
    );
    if (!unlocked) {
      if (mounted) setState(() => _errorMsg = S.t('biometric_failed'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    final error = await auth.signIn(creds.email, creds.password);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      setState(() => _errorMsg = error);
    }
    // On success the router auto-navigates away via AuthNotifier status change.
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final auth = context.read<AuthNotifier>();
    final error = await auth.signIn(email, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }

    if (auth.shouldPromptBiometricEnable && mounted) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            S.t('biometric_prompt_title'),
            style: AppTextStyles.headlineSm,
          ),
          content: Text(
            S.t('biometric_prompt_msg'),
            style: AppTextStyles.bodyMd,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                S.t('not_now'),
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                S.t('enable'),
                style: AppTextStyles.labelMd.copyWith(color: Colors.black),
              ),
            ),
          ],
        ),
      );

      if (result == true) {
        final userId =
            auth.profile?.id ?? SupabaseService.auth.currentUser?.id;
        if (userId != null) {
          final success = await BiometricService.instance.authenticate(
            localizedReason: S.t('biometric_enable_reason'),
          );
          if (success) {
            await BiometricService.instance.setBiometricEnabled(userId, true);
            // Save the credentials just entered so the user can sign in with
            // fingerprint next time (even after an explicit logout).
            await BiometricService.instance.saveCredentials(email, password);
          }
        }
      }
      auth.completeBiometricPrompt();
    } else {
      // Biometric not being prompted (already enabled, or unavailable). If it's
      // enabled, refresh the stored credentials so fingerprint login keeps
      // working after a password change.
      final userId = auth.profile?.id ?? SupabaseService.auth.currentUser?.id;
      if (userId != null &&
          await BiometricService.instance.isBiometricEnabled(userId)) {
        await BiometricService.instance.saveCredentials(email, password);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeCtrl = context.watch<LocaleController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              const SizedBox(height: 48),
              // Brand & Language Toggle
              Row(
                children: [
                  Container(
                    height: 70,
                    width: 120,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('CashBack', style: AppTextStyles.headlineMd),
                  const Spacer(),
                  // Language quick button
                  InkWell(
                    onTap: () => localeCtrl.toggleLanguage(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language, color: AppColors.gold, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            localeCtrl.isArabic ? 'English' : 'العربية',
                            style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Text(S.t('welcome_back'), style: AppTextStyles.displayMd),
              const SizedBox(height: 6),
              Text(
                S.t('login_sub'),
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),

              // Error banner
              if (_errorMsg != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Email
              Text(S.t('email').toUpperCase(), style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: AppTextStyles.bodyMd,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  hintText: 'you@company.com',
                  prefixIcon: Icon(Icons.email_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 20),

              // Password
              Text(S.t('password').toUpperCase(), style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: AppTextStyles.bodyMd,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: Text(
                    S.t('forgot_password'),
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Sign In button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(S.t('login')),
                ),
              ),

              // Fingerprint login option — only when the device has biometrics
              // AND credentials were saved when biometric login was enabled.
              if (_biometricAvailable && _hasStoredCreds) ...[
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _loading ? null : _biometricLogin,
                        borderRadius: BorderRadius.circular(40),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Icon(
                            Icons.fingerprint,
                            color: AppColors.gold,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.t('login_with_fingerprint'),
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Create account link
              Center(
                child: GestureDetector(
                  onTap: () => context.push('/signup'),
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.bodyMd,
                      children: [
                        TextSpan(
                          text: "${S.t('dont_have_account')} ",
                          style: AppTextStyles.bodySm,
                        ),
                        TextSpan(
                          text: S.t('signup'),
                          style: AppTextStyles.labelMd.copyWith(
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: Text(
                  '© 2025 CashBack · All rights reserved',
                  style: AppTextStyles.bodySm,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
