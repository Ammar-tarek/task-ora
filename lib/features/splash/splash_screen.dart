import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _promptingBiometrics = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkBiometricStatus();
  }

  void _checkBiometricStatus() {
    final auth = context.watch<AuthNotifier>();
    if (auth.status == AuthStatus.biometricRequired && !_promptingBiometrics) {
      _promptingBiometrics = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ok = await context.read<AuthNotifier>().authenticateBiometrics();
        if (mounted && !ok) {
          setState(() => _promptingBiometrics = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthNotifier, AuthStatus>((a) => a.status);
    final isBiometricRequired = status == AuthStatus.biometricRequired;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'CashBack',
                  style: AppTextStyles.displayMd.copyWith(
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Operations Dashboard',
                  style: AppTextStyles.labelCaps.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 48),
                if (isBiometricRequired) ...[
                  ElevatedButton.icon(
                    onPressed: _promptingBiometrics
                        ? null
                        : () async {
                            setState(() => _promptingBiometrics = true);
                            final ok = await context
                                .read<AuthNotifier>()
                                .authenticateBiometrics();
                            if (mounted && !ok) {
                              setState(() => _promptingBiometrics = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.fingerprint, size: 22),
                    label: Text(
                      S.t('unlock_with_biometrics'),
                      style: AppTextStyles.labelMd.copyWith(color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await context.read<AuthNotifier>().signOut();
                    },
                    child: Text(
                      S.t('login'),
                      style: AppTextStyles.bodySm.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: 28,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white10,
                      color: AppColors.gold,
                      minHeight: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
