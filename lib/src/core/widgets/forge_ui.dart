import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../branding/app_branding.dart';
import '../theme/app_theme.dart';
import '../theme/forge_palette.dart';

class ForgeScreen extends StatelessWidget {
  const ForgeScreen({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 32),
    this.useSafeArea = true,
    this.maxContentWidth = 1200,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool useSafeArea;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: ForgeAiTheme.backgroundGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _ForgeBackdrop(),
          LayoutBuilder(
            builder: (context, constraints) {
              final resolvedPadding = padding.resolve(
                Directionality.of(context),
              );
              final compactHorizontal = constraints.maxWidth < 360
                  ? 16.0
                  : constraints.maxWidth < 420
                  ? 20.0
                  : resolvedPadding.left;
              final contentInset = math.max(
                0,
                (constraints.maxWidth - maxContentWidth) / 2,
              );
              final content = Padding(
                padding: EdgeInsets.fromLTRB(
                  compactHorizontal + contentInset,
                  resolvedPadding.top,
                  compactHorizontal + contentInset,
                  resolvedPadding.bottom,
                ),
                child: child,
              );
              return useSafeArea ? SafeArea(child: content) : content;
            },
          ),
        ],
      ),
    );
  }
}

class ForgePanel extends StatefulWidget {
  const ForgePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.onTap,
    this.margin,
    this.backgroundColor,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final bool highlight;

  @override
  State<ForgePanel> createState() => _ForgePanelState();
}

class _ForgePanelState extends State<ForgePanel> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final glowColor = widget.highlight
        ? ForgePalette.glowAccent.withValues(alpha: 0.18)
        : ForgePalette.primaryAccent.withValues(alpha: 0.06);
    final borderColor = _hovered || _pressed
        ? ForgePalette.glowAccent.withValues(alpha: 0.4)
        : ForgePalette.border.withValues(alpha: 0.8);
    final backgroundColor =
        widget.backgroundColor ??
        (widget.highlight
            ? ForgePalette.surfaceElevated
            : ForgePalette.surface);
    final backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        backgroundColor.withValues(alpha: 0.98),
        (widget.highlight ? ForgePalette.surfaceTint : ForgePalette.surface)
            .withValues(alpha: 0.88),
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: _pressed ? 0.992 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: widget.margin,
          decoration: BoxDecoration(
            gradient: backgroundGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 34,
                spreadRadius: -16,
                offset: const Offset(0, 20),
              ),
              if (widget.highlight || _hovered)
                BoxShadow(
                  color: glowColor,
                  blurRadius: _hovered ? 28 : 20,
                  spreadRadius: -10,
                  offset: const Offset(0, 14),
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: widget.onTap,
              onHighlightChanged: (value) {
                setState(() => _pressed = value);
              },
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class ForgeAnimatedSwap extends StatelessWidget {
  const ForgeAnimatedSwap({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 440),
    this.reverseDuration,
    this.layoutBuilder = AnimatedSwitcher.defaultLayoutBuilder,
  });

  final Widget child;
  final Duration duration;
  final Duration? reverseDuration;
  final AnimatedSwitcherLayoutBuilder layoutBuilder;

  static Widget defaultTransitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration ?? duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: layoutBuilder,
      transitionBuilder: defaultTransitionBuilder,
      child: child,
    );
  }
}

class ForgeReveal extends StatefulWidget {
  const ForgeReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.beginOffset = const Offset(0, 0.05),
    this.beginScale = 0.985,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;
  final double beginScale;

  @override
  State<ForgeReveal> createState() => _ForgeRevealState();
}

class _ForgeRevealState extends State<ForgeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant ForgeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  void _scheduleReveal() {
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (!mounted || _controller.isAnimating || _controller.value > 0) {
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.beginOffset,
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: widget.beginScale,
            end: 1,
          ).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

class ForgePrimaryButton extends StatelessWidget {
  const ForgePrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = _ForgeButtonShell(
      onPressed: onPressed,
      gradient: ForgePalette.buttonGradient,
      borderColor: ForgePalette.glowAccent.withValues(alpha: 0.28),
      shadowColor: ForgePalette.glowAccent.withValues(alpha: 0.32),
      foreground: ForgePalette.textPrimary,
      icon: icon,
      label: label,
    );
    return _wrapButton(context, button);
  }

  Widget _wrapButton(BuildContext context, Widget button) {
    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _adaptiveLooseWidth(context)),
      child: button,
    );
  }
}

class ForgeSecondaryButton extends StatelessWidget {
  const ForgeSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = _ForgeButtonShell(
      onPressed: onPressed,
      background: ForgePalette.backgroundSecondary,
      borderColor: ForgePalette.border,
      foreground: ForgePalette.textPrimary,
      icon: icon,
      label: label,
    );
    return _wrapButton(context, button);
  }

  Widget _wrapButton(BuildContext context, Widget button) {
    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _adaptiveLooseWidth(context)),
      child: button,
    );
  }
}

class _ForgeButtonShell extends StatefulWidget {
  const _ForgeButtonShell({
    required this.label,
    required this.onPressed,
    required this.foreground,
    this.icon,
    this.gradient,
    this.background,
    this.borderColor,
    this.shadowColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color foreground;
  final IconData? icon;
  final Gradient? gradient;
  final Color? background;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  State<_ForgeButtonShell> createState() => _ForgeButtonShellState();
}

class _ForgeButtonShellState extends State<_ForgeButtonShell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: _pressed && !disabled ? 0.97 : 1,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: disabled ? 0.55 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: widget.gradient,
            color: widget.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.borderColor ?? Colors.transparent),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 18,
                spreadRadius: -10,
                offset: const Offset(0, 12),
              ),
              if (widget.shadowColor != null)
                BoxShadow(
                  color: widget.shadowColor!,
                  blurRadius: 24,
                  spreadRadius: -10,
                  offset: const Offset(0, 14),
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onPressed,
              onHighlightChanged: (value) {
                setState(() => _pressed = value);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 16, color: widget.foreground),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: widget.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ForgeSectionHeader extends StatelessWidget {
  const ForgeSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (trailing == null) {
          return textBlock;
        }

        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [textBlock, const SizedBox(height: 12), trailing!],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: textBlock),
            const SizedBox(width: 12),
            trailing!,
          ],
        );
      },
    );
  }
}

class ForgePill extends StatelessWidget {
  const ForgePill({
    super.key,
    required this.label,
    this.color = ForgePalette.glowAccent,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: _adaptiveLooseWidth(context, max: 280, min: 120),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: -12,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgeCodeBlock extends StatelessWidget {
  const ForgeCodeBlock({
    super.key,
    required this.lines,
    this.lineColors,
    this.padding = const EdgeInsets.all(16),
  });

  final List<String> lines;
  final List<Color?>? lineColors;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ForgePalette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lines.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${(index + 1).toString().padLeft(2, '0')}  ${lines[index]}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  height: 1.6,
                  color: lineColors == null
                      ? ForgePalette.textPrimary
                      : lineColors![index] ?? ForgePalette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ForgeAiIndicator extends StatefulWidget {
  const ForgeAiIndicator({super.key, this.label = 'AI processing'});

  final String label;

  @override
  State<ForgeAiIndicator> createState() => _ForgeAiIndicatorState();
}

class _ForgeAiIndicatorState extends State<ForgeAiIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final offset = index / 3;
                final progress = ((_controller.value - offset) % 1).clamp(0, 1);
                final scale = 0.75 + (0.45 * (1 - (progress - 0.5).abs() * 2));
                return Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: ForgePalette.glowAccent.withValues(
                      alpha: 0.35 + (0.55 * scale),
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: ForgePalette.glowAccent.withValues(
                          alpha: 0.22 + (0.25 * scale),
                        ),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            widget.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
          ),
        ),
      ],
    );
  }
}

class ForgeShimmerBlock extends StatefulWidget {
  const ForgeShimmerBlock({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.radius = 14,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<ForgeShimmerBlock> createState() => _ForgeShimmerBlockState();
}

class _ForgeShimmerBlockState extends State<ForgeShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + (_controller.value * 2), 0),
              end: Alignment(1 + (_controller.value * 2), 0),
              colors: const [
                ForgePalette.surface,
                Color(0xFF243041),
                ForgePalette.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

class ForgeBrandMark extends StatelessWidget {
  const ForgeBrandMark({
    super.key,
    this.size = 68,
    this.showText = false,

    /// When true, the mark is drawn with [BoxFit.contain] and no rounded clip or
    /// card shadow so a transparent PNG blends with the screen (e.g. splash).
    this.blendWithBackground = false,
  });

  final double size;
  final bool showText;
  final bool blendWithBackground;

  @override
  Widget build(BuildContext context) {
    final Widget markImage = Image.asset(
      'assets/branding/forge_mark.png',
      fit: blendWithBackground ? BoxFit.contain : BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );

    final Widget brand = blendWithBackground
        ? SizedBox(width: size, height: size, child: markImage)
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.28),
              boxShadow: [
                BoxShadow(
                  color: ForgePalette.glowAccent.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: -6,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: markImage,
          );

    if (!showText) {
      return brand;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textLockup = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kAppDisplayName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Control your code from anywhere',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );

        if (constraints.maxWidth.isFinite && constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [brand, const SizedBox(height: 12), textLockup],
          );
        }

        return Row(
          children: [
            brand,
            const SizedBox(width: 12),
            Flexible(child: textLockup),
          ],
        );
      },
    );
  }
}

class ForgeMetricTile extends StatelessWidget {
  const ForgeMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent = ForgePalette.glowAccent,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

double _adaptiveLooseWidth(
  BuildContext context, {
  double max = 320,
  double min = 160,
}) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.max(min, math.min(max, screenWidth - 48));
}

class _ForgeBackdrop extends StatelessWidget {
  const _ForgeBackdrop();

  @override
  Widget build(BuildContext context) {
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
          Positioned.fill(child: CustomPaint(painter: _ForgeGridPainter())),
          Positioned(
            top: -60,
            right: -40,
            child: _GlowOrb(
              color: ForgePalette.glowAccent.withValues(alpha: 0.16),
              size: 240,
            ),
          ),
          Positioned(
            top: 200,
            left: -80,
            child: _GlowOrb(
              color: ForgePalette.primaryAccent.withValues(alpha: 0.10),
              size: 200,
            ),
          ),
          Positioned(
            bottom: -120,
            right: -20,
            child: _GlowOrb(
              color: ForgePalette.sparkAccent.withValues(alpha: 0.12),
              size: 300,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _ForgeGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final horizontalPaint = Paint()
      ..color = ForgePalette.border.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    const step = 46.0;

    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontalPaint);
    }

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), horizontalPaint);
    }

    final diagonalPaint = Paint()
      ..color = ForgePalette.glowAccent.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const diagonalStep = 140.0;
    for (
      double start = -size.height;
      start <= size.width;
      start += diagonalStep
    ) {
      canvas.drawLine(
        Offset(start, 0),
        Offset(start + size.height, size.height),
        diagonalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
