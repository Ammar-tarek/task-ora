// lib/features/auth/signup_screen.dart
// First user to register automatically becomes Admin.
// Handles both: immediate redirect (email confirm OFF) and verify-email state (confirm ON).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/theme/app_theme.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _loading = false;
  String? _error;

  // True when Supabase requires email verification before login
  bool _awaitingEmailConfirmation = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm = _confCtrl.text;

    // ── Local validation ────────────────────────────────────────────────────
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await context.read<AuthNotifier>().signUp(
      email: email,
      password: password,
      fullName: name,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result == null) {
      // ✅ Session active immediately — GoRouter's refreshListenable fires and
      // redirects to /dashboard or /tasks automatically. Nothing to do here.
      return;
    }

    if (result == kEmailConfirmationRequired) {
      // ✅ Account created but email verification is required first
      setState(() => _awaitingEmailConfirmation = true);
      return;
    }

    // ❌ An error message was returned — show it
    setState(() => _error = result);
  }

  // ── Email confirmation waiting state ─────────────────────────────────────

  Widget _buildEmailConfirmationView() {
    final email = _emailCtrl.text.trim();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: AppColors.gold,
                size: 40,
              ),
            ),
            const SizedBox(height: 28),
            Text('Check your inbox', style: AppTextStyles.displayMd),
            const SizedBox(height: 12),
            Text(
              'We sent a verification link to:\n$email',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Click the link in the email to verify your account,\nthen come back and sign in.',
              style: AppTextStyles.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login_outlined),
                label: const Text('Go to Sign In'),
                onPressed: () => context.go('/login'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  setState(() => _awaitingEmailConfirmation = false),
              child: Text(
                'Use a different email',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Registration form ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _awaitingEmailConfirmation
            ? _buildEmailConfirmationView()
            : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),

          // Back button
          GestureDetector(
            onTap: () => context.go('/login'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Back to Sign In',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Brand
          Row(
            children: [
              Container(
                height: 70,
                width: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
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
              Text('CB TO-DO', style: AppTextStyles.headlineMd),
            ],
          ),
          const SizedBox(height: 32),

          Text('Create your account', style: AppTextStyles.displayMd),
          const SizedBox(height: 8),

          // Admin callout
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The first account created becomes the Admin.\n'
                    'Every email must be unique across the workspace.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Error banner ───────────────────────────────────────────────────
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        // If duplicate email — offer to go to login instead
                        if (_error!.contains('already exists')) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Text(
                              'Sign in instead →',
                              style: AppTextStyles.labelMd.copyWith(
                                color: AppColors.error,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Full Name
          Text('FULL NAME', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyles.bodyMd,
            decoration: const InputDecoration(
              hintText: 'e.g. Sara Ahmed',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 20),

          // Email
          Text('EMAIL ADDRESS', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: AppTextStyles.bodyMd,
            decoration: const InputDecoration(
              hintText: 'you@company.com',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 20),

          // Password
          Text('PASSWORD', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            style: AppTextStyles.bodyMd,
            decoration: InputDecoration(
              hintText: 'Min. 6 characters',
              prefixIcon: const Icon(Icons.lock_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Confirm Password
          Text('CONFIRM PASSWORD', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          TextField(
            controller: _confCtrl,
            obscureText: _obscureConf,
            style: AppTextStyles.bodyMd,
            onSubmitted: (_) => _register(),
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              prefixIcon: const Icon(Icons.lock_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConf
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConf = !_obscureConf),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Register button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Creating account…'),
                      ],
                    )
                  : const Text('Create Account'),
            ),
          ),
          const SizedBox(height: 20),

          // Already have account
          Center(
            child: GestureDetector(
              onTap: () => context.go('/login'),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Already have an account? ',
                      style: AppTextStyles.bodySm,
                    ),
                    TextSpan(
                      text: 'Sign In',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
