import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/branding/app_branding.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late final AnimationController _ambient;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      label: 'Connect',
      title: 'Your code, anywhere',
      subtitle:
          'Connect GitHub. Browse repos, switch branches, and open files from your phone.',
      icon: Icons.folder_copy_rounded,
      accent: Color(0xFF60A5FA),
      heroOffsets: [Offset(0.2, 0.15), Offset(0.75, 0.35), Offset(0.1, 0.7)],
    ),
    _OnboardingPage(
      label: 'Build',
      title: 'Prompt to change code',
      subtitle:
          'Describe what you want in plain language. Get AI suggestions, review every change, and approve before it ships.',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFF38BDF8),
      heroOffsets: [Offset(0.7, 0.2), Offset(0.15, 0.5), Offset(0.6, 0.75)],
    ),
    _OnboardingPage(
      label: 'Ship',
      title: 'Review and ship',
      subtitle:
          'See diffs, commit, and open pull requests. You stay in control from first edit to merge.',
      icon: Icons.verified_rounded,
      accent: Color(0xFF34D399),
      heroOffsets: [Offset(0.25, 0.25), Offset(0.7, 0.6), Offset(0.05, 0.65)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _ambient.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
  }

  void _nextOrComplete() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;
    final page = _pages[_currentPage];
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: ForgeAiTheme.backgroundGradient,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _OnboardingBackdrop(),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kAppDisplayName,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: ForgePalette.textMuted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _StepChip(
                                current: _currentPage + 1,
                                total: _pages.length,
                                accent: page.accent,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: isLast ? null : widget.onComplete,
                          style: TextButton.styleFrom(
                            foregroundColor: ForgePalette.textSecondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: _pages.length,
                      itemBuilder: (context, index) {
                        return _OnboardingPageView(
                          page: _pages[index],
                          ambient: _ambient,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _OnboardingBottomBar(
                bottomInset: bottomInset,
                pageCount: _pages.length,
                currentPage: _currentPage,
                isLast: isLast,
                onPrimary: _nextOrComplete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.current,
    required this.total,
    required this.accent,
  });

  final int current;
  final int total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            ForgePalette.surface.withValues(alpha: 0.45),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_graph_rounded,
            size: 14,
            color: accent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 8),
          Text(
            'Step $current of $total',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ForgePalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingBottomBar extends StatelessWidget {
  const _OnboardingBottomBar({
    required this.bottomInset,
    required this.pageCount,
    required this.currentPage,
    required this.isLast,
    required this.onPrimary,
  });

  final double bottomInset;
  final int pageCount;
  final int currentPage;
  final bool isLast;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: ForgePalette.border.withValues(alpha: 0.55),
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ForgePalette.backgroundSecondary.withValues(alpha: 0.72),
                ForgePalette.background.withValues(alpha: 0.88),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pageCount, (i) {
                    final active = i == currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      height: 8,
                      width: active ? 32 : 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: active
                            ? ForgePalette.buttonGradient
                            : null,
                        color: active
                            ? null
                            : ForgePalette.textMuted.withValues(alpha: 0.35),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: ForgePalette.glowAccent
                                      .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  spreadRadius: -2,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ForgePrimaryButton(
                    label: isLast ? 'Get started' : 'Continue',
                    icon: isLast
                        ? Icons.rocket_launch_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: onPrimary,
                    expanded: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.heroOffsets,
  });

  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Offset> heroOffsets;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({
    required this.page,
    required this.ambient,
  });

  final _OnboardingPage page;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 160),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          SizedBox(
            height: 300,
            child: _OnboardingHero(
              icon: page.icon,
              accent: page.accent,
              offsets: page.heroOffsets,
              ambient: ambient,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            page.label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: page.accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          _GradientTitle(text: page.title),
          const SizedBox(height: 16),
          Text(
            page.subtitle,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: ForgePalette.textSecondary,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GradientTitle extends StatelessWidget {
  const _GradientTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ForgePalette.textPrimary,
            ForgePalette.textPrimary.withValues(alpha: 0.92),
            ForgePalette.glowAccent.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
      },
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: -0.6,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero({
    required this.icon,
    required this.accent,
    required this.offsets,
    required this.ambient,
  });

  final IconData icon;
  final Color accent;
  final List<Offset> offsets;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: ambient,
          builder: (context, child) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OnboardingHeroPainter(
                offsets: offsets,
                accent: accent,
                rotation: ambient.value * 2 * math.pi,
              ),
              child: child,
            );
          },
          child: Center(
            child: _HeroOrb(icon: icon, accent: accent),
          ),
        );
      },
    );
  }
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({
    required this.icon,
    required this.accent,
  });

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 36,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.4),
                  radius: 1.15,
                  colors: [
                    accent.withValues(alpha: 0.5),
                    ForgePalette.primaryAccent.withValues(alpha: 0.22),
                    ForgePalette.surfaceElevated.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.transparent,
                      accent.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ForgePalette.surface.withValues(alpha: 0.55),
                      ForgePalette.surfaceElevated.withValues(alpha: 0.35),
                    ],
                  ),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: ForgePalette.textPrimary,
                  shadows: [
                    Shadow(
                      color: accent.withValues(alpha: 0.55),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingHeroPainter extends CustomPainter {
  _OnboardingHeroPainter({
    required this.offsets,
    required this.accent,
    required this.rotation,
  });

  final List<Offset> offsets;
  final Color accent;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.42;

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (var i = 0; i < 3; i++) {
      final t = i / 3.0;
      orbitPaint.color = accent.withValues(alpha: 0.08 + t * 0.1);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * (i == 0 ? 1 : (i == 1 ? -0.65 : 0.4)));
      canvas.translate(-center.dx, -center.dy);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: r * (2.1 + i * 0.38), height: r * (1.55 + i * 0.22)),
        orbitPaint,
      );
      canvas.restore();
    }

    final glow = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final c = Offset(o.dx * size.width, o.dy * size.height);
      final radius = size.shortestSide * (0.2 + (i * 0.055));
      final gradient = RadialGradient(
        colors: [
          (i == 0 ? accent : ForgePalette.primaryAccent).withValues(alpha: 0.22),
          (i == 0 ? accent : ForgePalette.primaryAccent).withValues(alpha: 0.0),
        ],
      );
      glow.shader = gradient.createShader(
        Rect.fromCircle(center: c, radius: radius),
      );
      canvas.drawCircle(c, radius, glow);
    }

    final sparkPaint = Paint()
      ..color = ForgePalette.textPrimary.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final sparkR = size.shortestSide * 0.008;
    for (var s = 0; s < 10; s++) {
      final a = rotation + s * (math.pi / 5);
      final dist = r * (1.05 + (s % 3) * 0.12);
      final p = Offset(
        center.dx + math.cos(a) * dist,
        center.dy + math.sin(a) * dist * 0.72,
      );
      canvas.drawCircle(p, sparkR + (s.isEven ? 0.4 : 0), sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingHeroPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.accent != accent ||
        oldDelegate.offsets != offsets;
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: ForgePalette.backgroundGlow,
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ForgePalette.glowAccent.withValues(alpha: 0.14),
                    ForgePalette.glowAccent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 140,
            left: -100,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ForgePalette.primaryAccent.withValues(alpha: 0.1),
                    ForgePalette.primaryAccent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: h * 0.35,
            left: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ForgePalette.glowAccent.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
