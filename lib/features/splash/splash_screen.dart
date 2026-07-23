// lib/features/splash/splash_screen.dart
// Pure animated splash — NO manual navigation.
// The GoRouter redirect guard handles all routing once AuthNotifier resolves.

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    // No context.go() here — the router's refreshListenable handles it.
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 180, height: 180,
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
              Text('CB TO-DO',
                style: AppTextStyles.displayMd.copyWith(
                  color: Colors.white, letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text('Operations Dashboard',
                style: AppTextStyles.labelCaps.copyWith(
                  color: AppColors.gold, letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: 28,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white10,
                  color: AppColors.gold,
                  minHeight: 2,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
