import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';

class ForgeSplashScreen extends StatefulWidget {
  const ForgeSplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ForgeSplashScreen> createState() => _ForgeSplashScreenState();
}

class _ForgeSplashScreenState extends State<ForgeSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  bool _showChild = false;

  @override
  void initState() {
    super.initState();
    _runSequence();
  }

  Future<void> _runSequence() async {
    await _pulseController.forward();
    await _pulseController.reverse();
    await _pulseController.forward();
    await _pulseController.reverse();
    if (!mounted) {
      return;
    }
    setState(() => _showChild = true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showChild
          ? widget.child
          : _SplashStage(
              fadeController: _fadeController,
              pulseController: _pulseController,
            ),
    );
  }
}

class _SplashStage extends StatelessWidget {
  const _SplashStage({
    required this.fadeController,
    required this.pulseController,
  });

  final AnimationController fadeController;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: fadeController, curve: Curves.easeOut);
    final scale = Tween<double>(
      begin: 0.95,
      end: 1,
    ).animate(CurvedAnimation(parent: fadeController, curve: Curves.easeOut));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ForgeScreen(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              child: AnimatedBuilder(
                animation: pulseController,
                builder: (context, child) {
                  final glow = 24 + (pulseController.value * 14);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: ForgePalette.glowAccent.withValues(
                                alpha: 0.10 + (pulseController.value * 0.14),
                              ),
                              blurRadius: glow,
                              spreadRadius: -10,
                            ),
                          ],
                        ),
                        child: const ForgeBrandMark(size: 132),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'ForgeAI',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Control your code from anywhere',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
