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
      return _IvyLiquidGlassBackground(
        baseColor: baseColor,
        child: child,
      );
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
      duration: const Duration(seconds: 25),
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
        // Bottom-most layer: The animated liquid and fibers
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
        // Glass Layer 1: Screen-wide frosted plate
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.32),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Glass Layer 2: Inner floating pane (ambient occlusion shadows)
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.94,
            heightFactor: 0.88,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(48),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5),
                    blurRadius: 0.5,
                    offset: const Offset(0, -0.5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(48),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Top-most layer: Specular reflections and corner glints
        const CustomPaint(painter: _IvyGlassPlaneSpecularPainter()),
        widget.child,
      ],
    );
  }
}

/// Slow organic liquid blobs + flowing fibers/wires (achromatic reference).
class _IvyLiquidFlowPainter extends CustomPainter {
  _IvyLiquidFlowPainter({
    required this.base,
    required this.phase,
  });

  final Color base;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = phase * 2 * math.pi;

    // Solid achromatic base
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF2F2F5));

    // Deep base gradient
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFBFBFE),
            const Color(0xFFE8E8EC),
            const Color(0xFFDCDCE2),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Flowing "fibers" or "wires" (curved paths)
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFC8C8D2).withValues(alpha: 0.22);
    
    void drawWire(double startY, double amp, double freq, double offset) {
      final path = Path();
      path.moveTo(0, startY);
      for (var x = 0.0; x <= size.width; x += 10) {
        final y = startY + amp * math.sin(x * freq + t * 0.4 + offset);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wirePaint);
    }

    drawWire(size.height * 0.2, 45, 0.005, 0);
    drawWire(size.height * 0.45, 60, 0.003, 1.2);
    drawWire(size.height * 0.75, 40, 0.006, 2.5);

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

    // Large, subtle achromatic blobs
    blob(
      cx: size.width * (0.35 + 0.06 * math.sin(t * 0.35)),
      cy: size.height * (0.25 + 0.1 * math.cos(t * 0.25)),
      rx: size.width * 0.8,
      ry: size.height * 0.6,
      color: Colors.white.withValues(alpha: 0.75),
    );

    blob(
      cx: size.width * (0.75 + 0.08 * math.cos(t * 0.45)),
      cy: size.height * (0.65 + 0.07 * math.sin(t * 0.35)),
      rx: size.width * 0.7,
      ry: size.height * 0.5,
      color: const Color(0xFFE4E4E8).withValues(alpha: 0.65),
    );

    blob(
      cx: size.width * (0.45 + 0.05 * math.sin(t * 0.55)),
      cy: size.height * (0.85 + 0.04 * math.cos(t * 0.45)),
      rx: size.width * 0.9,
      ry: size.height * 0.55,
      color: const Color(0xFFF0F0F4).withValues(alpha: 0.55),
    );

    // Vignette / depth
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.02),
          ],
        ).createShader(rect),
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
