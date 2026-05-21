import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const String daisyTextureAssetPath =
    'assets/c__Users_smadh_AppData_Roaming_Cursor_User_workspaceStorage_0dbfe92190d87ed8cf776b817604569f_images_image-9647ab36-e7ec-435e-afe7-d85d50b88632.png';
const String leahTextureAssetPath =
    'assets/c__Users_smadh_AppData_Roaming_Cursor_User_workspaceStorage_0dbfe92190d87ed8cf776b817604569f_images_image-f44a8fb3-4799-4ae6-8d61-ac2e01f71443.png';

class DaisyBackground extends StatelessWidget {
  const DaisyBackground({super.key, required this.baseColor, required this.child});

  final Color baseColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appliedThemePalette;
    final daisy = palette == AppThemePalette.daisy;
    final leah = palette == AppThemePalette.leah;
    final ivy = palette == AppThemePalette.ivy;
    if (!daisy && !leah && !ivy) {
      return ColoredBox(color: baseColor, child: child);
    }
    if (ivy) {
      return _IvyLiquidGlassBackground(baseColor: baseColor, child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (daisy) CustomPaint(painter: _DaisyPaperTexturePainter(baseColor)),
        if (leah) CustomPaint(painter: _LeahPaperTexturePainter(baseColor)),
        Opacity(
          opacity: daisy ? 0.58 : 0.5,
          child: Image.asset(
            daisy ? daisyTextureAssetPath : leahTextureAssetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        child,
      ],
    );
  }
}

/// Ivy scaffold: organic liquid layer → frosted blur veil → specular glass → UI.
class _IvyLiquidGlassBackground extends StatefulWidget {
  const _IvyLiquidGlassBackground({
    required this.baseColor,
    required this.child,
  });

  final Color baseColor;
  final Widget child;

  @override
  State<_IvyLiquidGlassBackground> createState() =>
      _IvyLiquidGlassBackgroundState();
}

class _IvyLiquidGlassBackgroundState extends State<_IvyLiquidGlassBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Bottom-most layer: The animated liquid
        AnimatedBuilder(
          animation: _flow,
          builder: (context, _) {
            return CustomPaint(
              painter: _IvyLiquidFlowPainter(
                base: widget.baseColor,
                phase: _flow.value,
              ),
            );
          },
        ),
        // Middle layer: The "inner plate (scrim)" - frosted glass effect
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.28),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Top-most layer: "outer glass shell" with specular reflections
        const CustomPaint(painter: _IvyGlassPlaneSpecularPainter()),
        widget.child,
      ],
    );
  }
}

/// Slow organic liquid blobs + waves (bottom-heavy, reference-style).
class _IvyLiquidFlowPainter extends CustomPainter {
  _IvyLiquidFlowPainter({required this.base, required this.phase});

  final Color base;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = phase * 2 * math.pi;

    canvas.drawRect(rect, Paint()..color = base);

    // Deep base gradient for the "liquid" container
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF8F8FA),
            base,
            const Color(0xFFE2E2E8),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    void blob({
      required double cx,
      required double cy,
      required double rx,
      required double ry,
      required Color color,
    }) {
      final oval = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawOval(
        oval,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(oval),
      );
    }

    // Larger, softer white blobs to match the "liquid card" reference
    blob(
      cx: size.width * (0.3 + 0.08 * math.sin(t * 0.4)),
      cy: size.height * (0.2 + 0.12 * math.cos(t * 0.3)),
      rx: size.width * 0.7,
      ry: size.height * 0.5,
      color: Colors.white.withValues(alpha: 0.65),
    );

    blob(
      cx: size.width * (0.8 + 0.1 * math.cos(t * 0.5)),
      cy: size.height * (0.6 + 0.08 * math.sin(t * 0.4)),
      rx: size.width * 0.6,
      ry: size.height * 0.4,
      color: const Color(0xFFECECEF).withValues(alpha: 0.7),
    );

    blob(
      cx: size.width * (0.4 + 0.05 * math.sin(t * 0.6)),
      cy: size.height * (0.8 + 0.05 * math.cos(t * 0.5)),
      rx: size.width * 0.8,
      ry: size.height * 0.5,
      color: const Color(0xFFF2F2F5).withValues(alpha: 0.6),
    );

    _drawLiquidWave(
      canvas,
      size,
      baseY: size.height * 0.65,
      amplitude: size.height * 0.08,
      phase: t,
      color: Colors.white.withValues(alpha: 0.45),
    );

    _drawLiquidWave(
      canvas,
      size,
      baseY: size.height * 0.82,
      amplitude: size.height * 0.06,
      phase: t + 1.8,
      color: const Color(0xFFF0F0F4).withValues(alpha: 0.55),
    );

    // Subtle overall highlight sheen
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -0.7),
          radius: 1.4,
          colors: [
            Colors.white.withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  void _drawLiquidWave(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amplitude,
    required double phase,
    required Color color,
  }) {
    final path = Path()..moveTo(0, size.height);
    const segments = 6;
    final segW = size.width / segments;
    for (var i = 0; i <= segments; i++) {
      final x = i * segW;
      final y = baseY +
          amplitude * math.sin((i / segments) * math.pi * 2 + phase);
      if (i == 0) {
        path.lineTo(0, y);
      } else {
        final prevX = (i - 1) * segW;
        final prevY = baseY +
            amplitude * math.sin(((i - 1) / segments) * math.pi * 2 + phase);
        final cx = (prevX + x) / 2;
        path.quadraticBezierTo(cx, (prevY + y) / 2, x, y);
      }
    }
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.15)],
        ).createShader(Rect.fromLTWH(0, baseY - amplitude, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _IvyLiquidFlowPainter old) =>
      old.base != base || old.phase != phase;
}

/// Diagonal sheen + corner highlights on the frosted glass plane (screen-wide).
class _IvyGlassPlaneSpecularPainter extends CustomPainter {
  const _IvyGlassPlaneSpecularPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Main diagonal sheen for the glass surface
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1.2, -1.2),
          end: const Alignment(1.0, 1.0),
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.05),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.08),
          ],
          stops: const [0.0, 0.35, 0.5, 0.7],
        ).createShader(rect),
    );

    // Subtle dark depth at the bottom right
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: const Alignment(-0.5, -0.5),
          colors: [
            const Color(0xFF000000).withValues(alpha: 0.03),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    void sharpHighlight(Alignment center, double radius, double alpha) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: center,
            radius: radius,
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }

    // Bright "glints" on the corners to match the liquid card shell
    sharpHighlight(const Alignment(-0.98, -0.98), 0.3, 0.6);
    sharpHighlight(const Alignment(0.96, -0.96), 0.15, 0.3);
    sharpHighlight(const Alignment(-0.96, 0.96), 0.15, 0.2);

    // Glass edge highlight (Top and Left)
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.8),
          Colors.white.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect.deflate(0.6));
    
    canvas.drawRect(rect.deflate(0.6), edgePaint);

    // Internal "bevel" light for 3D feel
    final bevelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.transparent,
        ],
      ).createShader(rect.deflate(1.5));
    canvas.drawRect(rect.deflate(1.5), bevelPaint);
  }

  @override
  bool shouldRepaint(covariant _IvyGlassPlaneSpecularPainter oldDelegate) =>
      false;
}

class _DaisyPaperTexturePainter extends CustomPainter {
  _DaisyPaperTexturePainter(this.base);

  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()..color = base;
    canvas.drawRect(rect, bg);

    final vignette = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD4C7B2), Color(0xFFBFB097)],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);

    final warmTint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.02, -0.25),
        radius: 1.25,
        colors: [
          const Color(0xFFE8DDC9).withValues(alpha: 0.22),
          const Color(0xFFA68F75).withValues(alpha: 0.08),
          const Color(0xFF000000).withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, warmTint);

    final dotDark = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.03);
    final dotLight = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.04);
    const step = 8.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        final seed = ((x * 13 + y * 17).toInt() % 11) / 11;
        if (seed > 0.62) {
          canvas.drawCircle(Offset(x + 1.5, y + 1.0), 0.85, dotDark);
        } else if (seed < 0.16) {
          canvas.drawCircle(Offset(x + 2.4, y + 2.2), 0.8, dotLight);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DaisyPaperTexturePainter oldDelegate) =>
      oldDelegate.base != base;
}

class _LeahPaperTexturePainter extends CustomPainter {
  _LeahPaperTexturePainter(this.base);

  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);

    final softPaper = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF5EFE6), Color(0xFFE9DFD0)],
      ).createShader(rect);
    canvas.drawRect(rect, softPaper);

    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.2),
        radius: 1.25,
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.2),
          const Color(0xFFE1D5C5).withValues(alpha: 0.16),
          const Color(0xFF000000).withValues(alpha: 0.04),
        ],
        stops: const [0.0, 0.68, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _LeahPaperTexturePainter oldDelegate) =>
      oldDelegate.base != base;
}
