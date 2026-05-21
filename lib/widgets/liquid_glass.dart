import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Visual presets aligned with [Backdrop](https://kyant.gitbook.io/backdrop)
/// (vibrancy → blur → lens → frosted surface).
class BackdropGlassStyle {
  const BackdropGlassStyle({
    required this.blurSigma,
    required this.lensStrength,
    required this.surfaceAlpha,
    required this.vibrancy,
    this.chromaticAberration = false,
    this.elevation = 1,
  });

  /// Bottom bar / large panels — `blur(4dp)` + `lens(16, 32)` per Backdrop tutorial.
  static const panel = BackdropGlassStyle(
    blurSigma: 14,
    lensStrength: 1.05,
    surfaceAlpha: 0.46,
    vibrancy: 1.18,
    chromaticAberration: true,
    elevation: 1.05,
  );

  /// Song cards and list tiles.
  static const card = BackdropGlassStyle(
    blurSigma: 11,
    lensStrength: 0.92,
    surfaceAlpha: 0.50,
    vibrancy: 1.14,
    chromaticAberration: true,
    elevation: 1.0,
  );

  /// Ivy library tiles — frosted blur, no drop shadow.
  static const cardPure = BackdropGlassStyle(
    blurSigma: 12,
    lensStrength: 0.96,
    surfaceAlpha: 0.44,
    vibrancy: 1.10,
    chromaticAberration: true,
    elevation: 0,
  );

  /// Circular / compact controls — `LiquidButton` uses tighter blur + lens.
  static const button = BackdropGlassStyle(
    blurSigma: 8,
    lensStrength: 0.78,
    surfaceAlpha: 0.54,
    vibrancy: 1.12,
    elevation: 0.75,
  );

  final double blurSigma;
  final double lensStrength;
  final double surfaceAlpha;
  final double vibrancy;
  final bool chromaticAberration;
  final double elevation;
}

/// Liquid glass surface inspired by
/// [AndroidLiquidGlass](https://github.com/Kyant0/AndroidLiquidGlass):
/// backdrop blur, vibrancy, lens rim, frosted surface, and specular highlights.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.shape = BoxShape.rectangle,
    this.padding,
    this.style = BackdropGlassStyle.card,
    this.prominence,
    this.onTap,
    this.width,
    this.height,
    this.clipChild = true,
    this.tintColor,
    this.borderColor,
    this.borderWidth = 1.25,
    this.elevation,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final BoxShape shape;
  final EdgeInsetsGeometry? padding;
  final BackdropGlassStyle style;

  /// Overrides [BackdropGlassStyle.surfaceAlpha] when set (0–1).
  final double? prominence;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final bool clipChild;
  final Color? tintColor;

  /// Optional accent rim (e.g. Ivy song cards).
  final Color? borderColor;
  final double borderWidth;

  /// Overrides [BackdropGlassStyle.elevation] for drop shadows.
  final double? elevation;

  static List<BoxShadow> shadows({double elevation = 1}) {
    if (elevation <= 0) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.14),
        blurRadius: 24 * elevation,
        offset: Offset(0, 10 * elevation),
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 8 * elevation,
        offset: Offset(0, 3 * elevation),
      ),
    ];
  }

  static BoxDecoration surfaceDecoration({
    required BoxShape shape,
    BorderRadius? borderRadius,
    required double surfaceAlpha,
    Color? tintColor,
  }) {
    final topAlpha = (surfaceAlpha * 1.12).clamp(0.0, 0.92);
    final bottomAlpha = (surfaceAlpha * 0.72).clamp(0.0, 0.75);
    return BoxDecoration(
      shape: shape,
      borderRadius: shape == BoxShape.circle ? null : borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: topAlpha),
          Colors.white.withValues(alpha: bottomAlpha),
        ],
      ),
    );
  }

  /// @deprecated Use [surfaceDecoration]; kept for mini-player call sites.
  static BoxDecoration decoration({
    required BoxShape shape,
    BorderRadius? borderRadius,
    double prominence = 0.55,
  }) =>
      surfaceDecoration(
        shape: shape,
        borderRadius: borderRadius,
        surfaceAlpha: (0.28 + prominence * 0.38).clamp(0.0, 0.88),
      );

  double get _surfaceAlpha =>
      prominence ?? style.surfaceAlpha;

  @override
  Widget build(BuildContext context) {
    final radius = shape == BoxShape.circle ? null : borderRadius;
    final surfaceAlpha = _surfaceAlpha;
    final content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );

    Widget glassLayers = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: surfaceDecoration(
              shape: shape,
              borderRadius: borderRadius,
              surfaceAlpha: surfaceAlpha,
            ),
          ),
        ),
        if (tintColor != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: shape,
                borderRadius: shape == BoxShape.circle ? null : borderRadius,
                color: tintColor!.withValues(alpha: 0.22),
              ),
            ),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: BackdropLiquidGlassPainter(
              shape: shape,
              borderRadius: borderRadius,
              lensStrength: style.lensStrength,
              chromaticAberration: style.chromaticAberration,
            ),
          ),
        ),
      ],
    );

    glassLayers = ColorFiltered(
      colorFilter: LiquidGlassSurface.vibrancyFilter(style.vibrancy),
      child: glassLayers,
    );

    glassLayers = BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: style.blurSigma,
        sigmaY: style.blurSigma,
      ),
      child: glassLayers,
    );

    Widget surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: glassLayers),
        if (clipChild && radius != null)
          ClipRRect(borderRadius: radius, child: content)
        else if (clipChild && shape == BoxShape.circle)
          ClipOval(child: content)
        else
          content,
      ],
    );

    if (radius != null) {
      surface = ClipRRect(borderRadius: radius, child: surface);
    } else if (shape == BoxShape.circle) {
      surface = ClipOval(child: surface);
    }

    surface = DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: shadows(elevation: elevation ?? style.elevation),
        border: borderColor != null && radius != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: surface,
    );

    if (width != null || height != null) {
      surface = SizedBox(width: width, height: height, child: surface);
    }

    if (onTap != null) {
      surface = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: shape == BoxShape.circle
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: borderRadius),
          splashColor: Colors.white.withValues(alpha: 0.20),
          highlightColor: Colors.white.withValues(alpha: 0.12),
          child: surface,
        ),
      );
    }

    return surface;
  }

  static ColorFilter vibrancyFilter(double amount) {
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final s = amount.clamp(0.5, 2.0);
    return ColorFilter.matrix([
      lumR + (1 - lumR) * s, lumG - lumG * s, lumB - lumB * s, 0, 0,
      lumR - lumR * s, lumG + (1 - lumG) * s, lumB - lumB * s, 0, 0,
      lumR - lumR * s, lumG - lumG * s, lumB + (1 - lumB) * s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Layered liquid-glass card — thick refractive outer frame + inset tinted plate
/// (reference-style double rim, prism corners, content on the plate).
class LiquidGlassLayerCard extends StatelessWidget {
  const LiquidGlassLayerCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(26)),
    this.frameWidth = 7,
    this.plateTint,
    this.accentColor,
    this.emphasized = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double frameWidth;
  final Color? plateTint;
  final Color? accentColor;
  final bool emphasized;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  static const double _blurSigma = 18;

  BorderRadius _innerRadius() {
    final r = borderRadius.topLeft.x;
    return BorderRadius.circular((r - frameWidth).clamp(14, 22));
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final plate = plateTint ?? accent;
    final innerRadius = _innerRadius();

    Widget layers = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: ColorFiltered(
          colorFilter: LiquidGlassSurface.vibrancyFilter(1.08),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: emphasized ? 0.34 : 0.26),
                        Colors.white.withValues(alpha: emphasized ? 0.12 : 0.07),
                        const Color(0xFFE8E6F0).withValues(alpha: 0.10),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _LiquidGlassOuterFramePainter(
                    borderRadius: borderRadius,
                    emphasized: emphasized,
                    accentHint: accent,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(frameWidth),
                child: ClipRRect(
                  borderRadius: innerRadius,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: innerRadius,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.82),
                                Color.alphaBlend(
                                  plate.withValues(alpha: emphasized ? 0.28 : 0.18),
                                  const Color(0xFFF6F4FA),
                                ),
                                Color.alphaBlend(
                                  plate.withValues(alpha: emphasized ? 0.22 : 0.12),
                                  const Color(0xFFEDEAF4),
                                ),
                              ],
                              stops: const [0.0, 0.42, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LiquidGlassInsetPlatePainter(
                            borderRadius: innerRadius,
                            emphasized: emphasized,
                          ),
                        ),
                      ),
                      Padding(padding: padding, child: child),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap != null) {
      layers = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          splashColor: Colors.white.withValues(alpha: 0.42),
          highlightColor: Colors.white.withValues(alpha: 0.22),
          child: layers,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: plate.withValues(alpha: emphasized ? 0.14 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.65),
            blurRadius: 0.5,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: layers,
    );
  }
}

/// Double rim + prism corner highlights on the outer glass bezel.
class _LiquidGlassOuterFramePainter extends CustomPainter {
  const _LiquidGlassOuterFramePainter({
    required this.borderRadius,
    required this.emphasized,
    required this.accentHint,
  });

  final BorderRadius borderRadius;
  final bool emphasized;
  final Color accentHint;

  RRect _rrect(Rect rect, double deflate) {
    final r = rect.deflate(deflate);
    final resolved = borderRadius.resolve(TextDirection.ltr);
    return RRect.fromRectAndCorners(
      r,
      topLeft: _clampRadius(resolved.topLeft, r),
      topRight: _clampRadius(resolved.topRight, r),
      bottomLeft: _clampRadius(resolved.bottomLeft, r),
      bottomRight: _clampRadius(resolved.bottomRight, r),
    );
  }

  Radius _clampRadius(Radius radius, Rect r) {
    final maxR = (r.shortestSide / 2).clamp(0.0, 999.0);
    return Radius.circular(radius.x.clamp(0.0, maxR));
  }

  void _strokeRim(
    Canvas canvas,
    RRect rrect,
    double strokeWidth,
    List<Color> colors,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rrect.outerRect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = _rrect(rect, 1.0);
    final inner = _rrect(rect, emphasized ? 4.8 : 5.5);

    _strokeRim(
      canvas,
      outer,
      emphasized ? 2.6 : 2.35,
      [
        Colors.white.withValues(alpha: 0.95),
        Colors.white.withValues(alpha: 0.55),
        Colors.white.withValues(alpha: 0.78),
      ],
    );
    _strokeRim(
      canvas,
      inner,
      1.15,
      [
        Colors.white.withValues(alpha: 0.62),
        Colors.white.withValues(alpha: 0.28),
        Colors.white.withValues(alpha: 0.40),
      ],
    );

    final prism = Paint()
      ..shader = SweepGradient(
        center: Alignment.topLeft,
        startAngle: -1.2,
        endAngle: 1.4,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          accentHint.withValues(alpha: 0.10),
          Colors.transparent,
          const Color(0xFF8EB4FF).withValues(alpha: 0.14),
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.45, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawRRect(outer, prism);

    final specular = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.85, -0.95),
        radius: 0.55,
        colors: [
          Colors.white.withValues(alpha: 0.75),
          Colors.white.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(rect);
    canvas.drawRRect(outer, specular);

    void chromaticStroke(Color color, Offset shift, double deflate) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = color;
      canvas.drawRRect(_rrect(rect.deflate(deflate).shift(shift), 0), paint);
    }

    chromaticStroke(
      const Color(0xFFFF7A7A).withValues(alpha: 0.16),
      const Offset(-0.6, 0),
      2.2,
    );
    chromaticStroke(
      const Color(0xFF7AB0FF).withValues(alpha: 0.14),
      const Offset(0.6, 0),
      2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassOuterFramePainter old) =>
      old.emphasized != emphasized || old.accentHint != accentHint;
}

/// Soft top shine + inner depth on the inset content plate.
class _LiquidGlassInsetPlatePainter extends CustomPainter {
  const _LiquidGlassInsetPlatePainter({
    required this.borderRadius,
    required this.emphasized,
  });

  final BorderRadius borderRadius;
  final bool emphasized;

  RRect _rrect(Rect rect) {
    final resolved = borderRadius.resolve(TextDirection.ltr);
    return RRect.fromRectAndCorners(
      rect,
      topLeft: resolved.topLeft,
      topRight: resolved.topRight,
      bottomLeft: resolved.bottomLeft,
      bottomRight: resolved.bottomRight,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = _rrect(rect);

    final topShine = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: emphasized ? 0.55 : 0.48),
          Colors.white.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.22, 0.55],
      ).createShader(rect);
    canvas.drawRRect(rrect, topShine);

    final bottomDepth = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35],
      ).createShader(rect);
    canvas.drawRRect(rrect, bottomDepth);

    final innerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.70),
          Colors.white.withValues(alpha: 0.22),
        ],
      ).createShader(rect.deflate(0.8));
    canvas.drawRRect(rrect.deflate(0.8), innerRim);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassInsetPlatePainter old) =>
      old.emphasized != emphasized;
}

/// Lens rim, chromatic edge, ambient highlight, and inner shadow (Backdrop-style).
class BackdropLiquidGlassPainter extends CustomPainter {
  const BackdropLiquidGlassPainter({
    this.shape = BoxShape.rectangle,
    this.borderRadius = BorderRadius.zero,
    this.lensStrength = 1,
    this.chromaticAberration = false,
  });

  final BoxShape shape;
  final BorderRadius borderRadius;
  final double lensStrength;
  final bool chromaticAberration;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintLensBody(canvas, rect);
    _paintAmbientHighlight(canvas, rect);
    _paintInnerShadow(canvas, rect);
    _paintLensRim(canvas, rect);
    if (chromaticAberration) {
      _paintChromaticRim(canvas, rect);
    }
  }

  void _paintLensBody(Canvas canvas, Rect rect) {
    final lens = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.92,
        colors: [
          Colors.white.withValues(alpha: 0.06 * lensStrength),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.14 * lensStrength),
        ],
        stops: const [0.35, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, lens);

    final warm = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.92, 0.94),
        radius: 0.55,
        colors: [
          const Color(0xFFFFE8C8).withValues(alpha: 0.12 * lensStrength),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, warm);
  }

  void _paintAmbientHighlight(Canvas canvas, Rect rect) {
    final specular = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.78, -0.92),
        radius: 1.1,
        colors: [
          Colors.white.withValues(alpha: 0.70),
          Colors.white.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.32, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, specular);

    final topRim = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.42),
          Colors.transparent,
        ],
        stops: const [0.0, 0.18],
      ).createShader(rect);
    canvas.drawRect(rect, topRim);
  }

  void _paintInnerShadow(Canvas canvas, Rect rect) {
    final depth = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.28],
      ).createShader(rect);
    canvas.drawRect(rect, depth);
  }

  void _paintLensRim(Canvas canvas, Rect rect) {
    final inset = 0.85;
    final stroke = 1.35 + lensStrength * 0.35;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.88),
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.62),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect.deflate(inset));

    if (shape == BoxShape.circle) {
      canvas.drawOval(rect.deflate(inset), rim);
    } else {
      final resolved = borderRadius.resolve(TextDirection.ltr);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect.deflate(inset),
          topLeft: resolved.topLeft,
          topRight: resolved.topRight,
          bottomLeft: resolved.bottomLeft,
          bottomRight: resolved.bottomRight,
        ),
        rim,
      );
    }
  }

  void _paintChromaticRim(Canvas canvas, Rect rect) {
    final inset = 1.1;
    final stroke = 1.0;
    void strokeRim(Color color, Offset offset) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color;
      final r = rect.deflate(inset).shift(offset);
      if (shape == BoxShape.circle) {
        canvas.drawOval(r, paint);
      } else {
        final resolved = borderRadius.resolve(TextDirection.ltr);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: resolved.topLeft,
            topRight: resolved.topRight,
            bottomLeft: resolved.bottomLeft,
            bottomRight: resolved.bottomRight,
          ),
          paint,
        );
      }
    }

    strokeRim(const Color(0xFFFF6B6B).withValues(alpha: 0.14), const Offset(-0.55, 0));
    strokeRim(const Color(0xFF6B9FFF).withValues(alpha: 0.12), const Offset(0.55, 0));
  }

  @override
  bool shouldRepaint(covariant BackdropLiquidGlassPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.lensStrength != lensStrength ||
      oldDelegate.chromaticAberration != chromaticAberration;
}

/// @deprecated Alias for [BackdropLiquidGlassPainter].
typedef LiquidGlassHighlightPainter = BackdropLiquidGlassPainter;

/// Icon with a subtle etched / embossed look on frosted glass.
class LiquidGlassEtchedIcon extends StatelessWidget {
  const LiquidGlassEtchedIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 24,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : color.withValues(alpha: 0.34);
    return Icon(
      icon,
      size: size,
      color: c,
      shadows: [
        Shadow(
          color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.55),
          offset: const Offset(0, -0.75),
        ),
        Shadow(
          color: Colors.black.withValues(alpha: enabled ? 0.14 : 0.08),
          offset: const Offset(0, 1.1),
          blurRadius: 1.2,
        ),
      ],
    );
  }
}

/// Frosted convex glass — backdrop blur, dual-tone rim, soft lift (reference controls).
class LiquidGlassConvexSurface extends StatelessWidget {
  const LiquidGlassConvexSurface({
    super.key,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.borderRadius = BorderRadius.zero,
    this.width,
    this.height,
    this.onTap,
    this.blurSigma = 16,
    this.prominence = 1.0,
  });

  final Widget child;
  final BoxShape shape;
  final BorderRadius borderRadius;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final double blurSigma;
  final double prominence;

  @override
  Widget build(BuildContext context) {
    final p = prominence.clamp(0.55, 1.25);
    final radius = shape == BoxShape.circle ? null : borderRadius;

    Widget glass = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: shape,
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.30 * p),
                  Colors.white.withValues(alpha: 0.14 * p),
                  Colors.white.withValues(alpha: 0.07 * p),
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _LiquidGlassConvexPainter(
              shape: shape,
              borderRadius: borderRadius,
            ),
          ),
        ),
        child,
      ],
    );

    glass = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: glass,
    );

    if (radius != null) {
      glass = ClipRRect(borderRadius: radius, child: glass);
    } else {
      glass = ClipOval(child: glass);
    }

    glass = DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 5),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.55),
            blurRadius: 0.5,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: glass,
    );

    if (width != null || height != null) {
      glass = SizedBox(width: width, height: height, child: glass);
    }

    if (onTap != null) {
      glass = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: shape == BoxShape.circle
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: borderRadius),
          splashColor: Colors.white.withValues(alpha: 0.28),
          highlightColor: Colors.white.withValues(alpha: 0.16),
          child: glass,
        ),
      );
    }

    return glass;
  }
}

/// Dual-tone rim + specular highlight + inner depth for [LiquidGlassConvexSurface].
class _LiquidGlassConvexPainter extends CustomPainter {
  const _LiquidGlassConvexPainter({
    required this.shape,
    required this.borderRadius,
  });

  final BoxShape shape;
  final BorderRadius borderRadius;

  RRect _rrect(Rect rect, [double deflate = 0.85]) {
    final r = rect.deflate(deflate);
    if (shape == BoxShape.circle) {
      return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    }
    final resolved = borderRadius.resolve(TextDirection.ltr);
    return RRect.fromRectAndCorners(
      r,
      topLeft: resolved.topLeft,
      topRight: resolved.topRight,
      bottomLeft: resolved.bottomLeft,
      bottomRight: resolved.bottomRight,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = _rrect(rect);

    final specular = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.82, -0.92),
        radius: 0.72,
        colors: [
          Colors.white.withValues(alpha: 0.62),
          Colors.white.withValues(alpha: 0.14),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, specular);

    final innerDepth = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.07),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38],
      ).createShader(rect);
    canvas.drawRRect(rrect, innerDepth);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.88),
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, rim);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassConvexPainter old) =>
      old.shape != shape || old.borderRadius != borderRadius;
}

/// Hollow circle control: transparent fill, accent-colored ring + icon.
class HollowAccentCircleButton extends StatelessWidget {
  const HollowAccentCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.accentColor,
    this.size = 48,
    this.iconSize = 28,
    this.ringWidth = 2.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color accentColor;
  final double size;
  final double iconSize;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? accentColor : accentColor.withValues(alpha: 0.38);
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(color: color, width: ringWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: CircleBorder(
            side: BorderSide(color: color, width: ringWidth),
          ),
          splashColor: accentColor.withValues(alpha: 0.12),
          highlightColor: accentColor.withValues(alpha: 0.06),
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: color,
              fill: 0,
              weight: 500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular frosted-glass control — convex lens + etched icon (reference style).
class LiquidGlassRingIconButton extends StatelessWidget {
  const LiquidGlassRingIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 56,
    this.iconSize = 26,
    this.accentColor,
    this.inactiveColor,
    this.disabledColor,
    this.highlighted = true,
    this.active = false,
    this.ringWidth = 1.85,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? accentColor;
  final Color? inactiveColor;
  final Color? disabledColor;
  final bool highlighted;
  /// When true, icon uses [accentColor]; otherwise dark ink on glass.
  final bool active;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final inactive = inactiveColor ?? const Color(0xFFC8C8CE);
    final disabled = disabledColor ?? inactive;
    final iconColor = !enabled
        ? disabled
        : active
        ? accent
        : inactive;

    return LiquidGlassConvexSurface(
      shape: BoxShape.circle,
      width: size,
      height: size,
      blurSigma: 14,
      prominence: enabled ? (highlighted ? 1.05 : 0.88) : 0.72,
      onTap: onPressed,
      child: Center(
        child: LiquidGlassEtchedIcon(
          icon: icon,
          size: iconSize,
          color: iconColor,
          enabled: enabled,
        ),
      ),
    );
  }
}

/// Squircle glass play/pause — circular ring style (reference play icon).
class LiquidGlassPlayButton extends StatelessWidget {
  const LiquidGlassPlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.width = 76,
    this.height = 76,
    this.iconSize = 34,
    this.accentColor,
    this.frameInset = 7,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final double iconSize;
  final Color? accentColor;
  final double frameInset;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassRingIconButton(
      icon: icon,
      onPressed: onPressed,
      size: width,
      iconSize: iconSize,
      accentColor: accentColor,
      highlighted: true,
      active: false,
      ringWidth: 2.0,
    );
  }
}

/// Back-compat wrapper — maps [iconColor] / [disabledColor] to ring button.
class LiquidGlassCircleButton extends StatelessWidget {
  const LiquidGlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 56,
    this.iconSize = 28,
    this.iconColor = const Color(0xFF1C1C1E),
    this.disabledColor = const Color(0xFFC7C7CC),
    this.prominence,
    this.highlighted = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color iconColor;
  final Color disabledColor;
  final double? prominence;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassRingIconButton(
      icon: icon,
      onPressed: onPressed,
      size: size,
      iconSize: iconSize,
      accentColor: iconColor,
      inactiveColor: disabledColor,
      highlighted: highlighted,
      active: true,
    );
  }
}
