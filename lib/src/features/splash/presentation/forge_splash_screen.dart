import 'package:flutter/material.dart';

import '../../../core/branding/app_branding.dart';
import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';

const _splashFadeDuration = Duration(milliseconds: 300);
const _splashPulseDuration = Duration(milliseconds: 520);
const _splashHoldDuration = Duration(milliseconds: 1300);
const _splashTransitionDuration = Duration(milliseconds: 400);

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
    duration: _splashFadeDuration,
  )..forward();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: _splashPulseDuration,
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
    await Future<void>.delayed(_splashHoldDuration);
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
    return ForgeAnimatedSwap(
      duration: _splashTransitionDuration,
      child: _showChild
          ? KeyedSubtree(
              key: const ValueKey('splash-child'),
              child: widget.child,
            )
          : _SplashStage(
              key: const ValueKey('splash-stage'),
              fadeController: _fadeController,
              pulseController: _pulseController,
            ),
    );
  }
}

class _SplashStage extends StatelessWidget {
  const _SplashStage({
    super.key,
    required this.fadeController,
    required this.pulseController,
  });

  final AnimationController fadeController;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ForgeScreen(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SplashAtmosphere(),
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([fadeController, pulseController]),
                builder: (context, child) {
                  final intro = Curves.easeOutCubic.transform(
                    fadeController.value,
                  );
                  final pulse = 1 + (pulseController.value * 0.04);
                  final haloScale =
                      0.95 + (pulseController.value * 0.1) + (intro * 0.05);
                  final drift = (pulseController.value - 0.5) * 18;
                  return Opacity(
                    opacity: intro,
                    child: Transform.translate(
                      offset: Offset(0, (1 - intro) * 24),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  ForgePill(
                                    label: 'Mobile Git workflow',
                                    icon: Icons.mobile_friendly_rounded,
                                    color: ForgePalette.sparkAccent,
                                  ),
                                  ForgePill(
                                    label: 'Secure sign in',
                                    icon: Icons.verified_user_rounded,
                                    color: ForgePalette.mintAccent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: 272,
                                height: 272,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.scale(
                                      scale: haloScale,
                                      child: const _SplashHalo(),
                                    ),
                                    Transform.translate(
                                      offset: Offset(82, -54 + (drift * 0.45)),
                                      child: const _SplashOrb(
                                        size: 66,
                                        color: ForgePalette.sparkAccent,
                                      ),
                                    ),
                                    Transform.translate(
                                      offset: Offset(-88, 70 - (drift * 0.35)),
                                      child: const _SplashOrb(
                                        size: 82,
                                        color: ForgePalette.mintAccent,
                                      ),
                                    ),
                                    Container(
                                      width: 198,
                                      height: 198,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            ForgePalette.surfaceElevated
                                                .withValues(alpha: 0.95),
                                            ForgePalette.surface.withValues(
                                              alpha: 0.74,
                                            ),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: ForgePalette.glowAccent
                                              .withValues(alpha: 0.18),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: ForgePalette.glowAccent
                                                .withValues(alpha: 0.12),
                                            blurRadius: 40,
                                            spreadRadius: -10,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 154,
                                          height: 154,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: ForgePalette.border
                                                  .withValues(alpha: 0.72),
                                            ),
                                            color: ForgePalette.background
                                                .withValues(alpha: 0.22),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Transform.scale(
                                      scale: pulse,
                                      child: const ForgeBrandMark(
                                        size: 132,
                                        blendWithBackground: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 26),
                              Text(
                                kAppDisplayName,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      fontSize: 36,
                                      letterSpacing: -0.8,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Review, edit, and ship code from anywhere.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: ForgePalette.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 18),
                              const Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  ForgePill(
                                    label: 'Readable diffs',
                                    icon: Icons.compare_arrows_rounded,
                                  ),
                                  ForgePill(
                                    label: 'AI suggestions',
                                    icon: Icons.auto_awesome_rounded,
                                  ),
                                  ForgePill(
                                    label: 'Safe approvals',
                                    icon: Icons.shield_moon_rounded,
                                    color: ForgePalette.mintAccent,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashAtmosphere extends StatelessWidget {
  const _SplashAtmosphere();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: const [
          Positioned(
            left: -120,
            top: -60,
            child: _SplashAura(
              size: 320,
              color: ForgePalette.glowAccent,
              opacity: 0.2,
            ),
          ),
          Positioned(
            right: -130,
            top: 140,
            child: _SplashAura(
              size: 280,
              color: ForgePalette.sparkAccent,
              opacity: 0.12,
            ),
          ),
          Positioned(
            left: 20,
            bottom: -150,
            child: _SplashAura(
              size: 300,
              color: ForgePalette.mintAccent,
              opacity: 0.12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashHalo extends StatelessWidget {
  const _SplashHalo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      height: 236,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            ForgePalette.glowAccent.withValues(alpha: 0.26),
            ForgePalette.glowAccent.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
    );
  }
}

class _SplashAura extends StatelessWidget {
  const _SplashAura({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.28),
            Colors.transparent,
          ],
          stops: const [0, 0.44, 1],
        ),
      ),
    );
  }
}

class _SplashOrb extends StatelessWidget {
  const _SplashOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.45),
            color.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0, 0.42, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 28,
            spreadRadius: -8,
          ),
        ],
      ),
    );
  }
}
