import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../theme/forge_palette.dart';

class ForgeScreen extends StatelessWidget {
  const ForgeScreen({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 28),
    this.useSafeArea = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: ForgeAiTheme.backgroundGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _ForgeBackdrop(),
          if (useSafeArea) SafeArea(child: content) else content,
        ],
      ),
    );
  }
}

class ForgePanel extends StatefulWidget {
  const ForgePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
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
        : ForgePalette.glowAccent.withValues(alpha: 0.08);
    final borderColor = _hovered || _pressed
        ? ForgePalette.glowAccent.withValues(alpha: 0.4)
        : ForgePalette.border;
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
            color: widget.backgroundColor ?? ForgePalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: glowColor,
                blurRadius: _hovered ? 20 : 14,
                spreadRadius: _hovered ? 0 : -6,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
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
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
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
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.borderColor ?? Colors.transparent),
            boxShadow: widget.shadowColor == null
                ? null
                : [
                    BoxShadow(
                      color: widget.shadowColor!,
                      blurRadius: 18,
                      spreadRadius: -8,
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onPressed,
              onHighlightChanged: (value) {
                setState(() => _pressed = value);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16, color: widget.foreground),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
        const SizedBox(height: 6),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ForgePalette.border),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
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
        Text(
          widget.label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
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
  const ForgeBrandMark({super.key, this.size = 68, this.showText = false});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final brand = Container(
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
      child: Image.asset('assets/branding/forge_mark.png', fit: BoxFit.cover),
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
              'ForgeAI',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Control your code from anywhere',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          Positioned(
            top: -80,
            right: -20,
            child: _GlowOrb(
              color: ForgePalette.glowAccent.withValues(alpha: 0.12),
              size: 220,
            ),
          ),
          Positioned(
            top: 180,
            left: -60,
            child: _GlowOrb(
              color: ForgePalette.primaryAccent.withValues(alpha: 0.08),
              size: 180,
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
