// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email    = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Please enter your email and password.');
      return;
    }

    setState(() { _loading = true; _errorMsg = null; });

    final auth  = context.read<AuthNotifier>();
    final error = await auth.signIn(email, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      setState(() => _errorMsg = error);
    }
    // On success: GoRouter's refreshListenable fires → redirect runs → done.
    // No manual context.go() needed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 48),
            // Brand
            Row(children: [
              Container(
                height: 70, width: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
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
            ]),
            const SizedBox(height: 48),
            Text('Welcome back', style: AppTextStyles.displayMd),
            const SizedBox(height: 6),
            Text('Sign in to your operations dashboard',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 40),

            // Error banner
            if (_errorMsg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_errorMsg!,
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
            ],

            // Email
            Text('EMAIL ADDRESS', style: AppTextStyles.labelCaps),
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
            Text('PASSWORD', style: AppTextStyles.labelCaps),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              style: AppTextStyles.bodyMd,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                hintText: 'Your password',
                prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined, size: 20),
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
                child: Text('Forgot password?',
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
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
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : const Text('Sign In'),
              ),
            ),
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
                        text: "Don't have an account? ",
                        style: AppTextStyles.bodySm,
                      ),
                      TextSpan(
                        text: 'Create Account',
                        style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Text('© 2025 CB TO-DO · All rights reserved',
                style: AppTextStyles.bodySm,
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
