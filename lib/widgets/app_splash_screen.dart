import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppSplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const AppSplashScreen({super.key, required this.onFinish});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), widget.onFinish);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/splash_background.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFFF5F5F7),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(300, 300),
                  painter: _LogoPainter(progress: _controller.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double progress;

  _LogoPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // We normalize the SVG coordinates (512x512) to our canvas size (300x300)
    double scale = size.width / 512;

    // Frequency Dots Data from SVG
    final dots = [
      // Column 1: Left Leg
      _Dot(125, 170, 10, 0.0, const Color(0xFF0B84FF)),
      _Dot(125, 206, 12, 0.05, const Color(0xFF0B84FF)),
      _Dot(125, 242, 14, 0.1, const Color(0xFF0B84FF)),
      _Dot(125, 278, 15, 0.15, const Color(0xFF0B84FF)),
      _Dot(125, 314, 14, 0.2, const Color(0xFF0B84FF)),
      _Dot(125, 350, 12, 0.25, const Color(0xFF0B84FF)),
      _Dot(125, 386, 10, 0.3, const Color(0xFF0B84FF)),

      _Dot(158, 190, 9, 0.1, const Color(0xFF4256FF)),
      _Dot(158, 226, 11, 0.15, const Color(0xFF4256FF)),
      _Dot(158, 262, 12, 0.2, const Color(0xFF4256FF)),
      _Dot(158, 298, 11, 0.25, const Color(0xFF4256FF)),
      _Dot(158, 334, 9, 0.3, const Color(0xFF4256FF)),
      _Dot(158, 370, 7, 0.35, const Color(0xFF4256FF)),

      // Column 2: First Valley
      _Dot(191, 210, 8, 0.2, const Color(0xFF7A28FF)),
      _Dot(191, 246, 10, 0.25, const Color(0xFF7A28FF)),
      _Dot(191, 282, 11, 0.3, const Color(0xFF7A28FF)),
      _Dot(191, 318, 10, 0.35, const Color(0xFF7A28FF)),
      _Dot(191, 354, 8, 0.4, const Color(0xFF7A28FF)),

      _Dot(224, 230, 7, 0.3, const Color(0xFFA100FF)),
      _Dot(224, 266, 9, 0.35, const Color(0xFFA100FF)),
      _Dot(224, 302, 8, 0.4, const Color(0xFFA100FF)),
      _Dot(224, 334, 6, 0.45, const Color(0xFFA100FF)),

      // Column 3: Center Peak / Dip Junction
      _Dot(256, 250, 6, 0.4, const Color(0xFFD000BD)),
      _Dot(256, 286, 8, 0.45, const Color(0xFFD000BD)),
      _Dot(256, 322, 6, 0.5, const Color(0xFFD000BD)),

      // Column 4: Second Valley
      _Dot(288, 230, 7, 0.5, const Color(0xFFFF007A)),
      _Dot(288, 266, 9, 0.55, const Color(0xFFFF007A)),
      _Dot(288, 302, 8, 0.6, const Color(0xFFFF007A)),
      _Dot(288, 334, 6, 0.65, const Color(0xFFFF007A)),

      _Dot(321, 210, 8, 0.6, const Color(0xFFD14B8D)),
      _Dot(321, 246, 10, 0.65, const Color(0xFFD14B8D)),
      _Dot(321, 282, 11, 0.7, const Color(0xFFD14B8D)),
      _Dot(321, 318, 10, 0.75, const Color(0xFFD14B8D)),
      _Dot(321, 354, 8, 0.8, const Color(0xFFD14B8D)),

      // Column 5: Right Leg
      _Dot(354, 190, 9, 0.7, const Color(0xFFA2979E)),
      _Dot(354, 226, 11, 0.75, const Color(0xFFA2979E)),
      _Dot(354, 262, 12, 0.8, const Color(0xFFA2979E)),
      _Dot(354, 298, 11, 0.85, const Color(0xFFA2979E)),
      _Dot(354, 334, 9, 0.9, const Color(0xFFA2979E)),
      _Dot(354, 370, 7, 0.95, const Color(0xFFA2979E)),

      _Dot(387, 170, 10, 0.8, const Color(0xFF5FE3B3)),
      _Dot(387, 206, 12, 0.85, const Color(0xFF5FE3B3)),
      _Dot(387, 242, 14, 0.9, const Color(0xFF5FE3B3)),
      _Dot(387, 278, 15, 0.95, const Color(0xFF5FE3B3)),
      _Dot(387, 314, 14, 1.0, const Color(0xFF5FE3B3)),
      _Dot(387, 350, 12, 1.05, const Color(0xFF5FE3B3)),
      _Dot(387, 386, 10, 1.1, const Color(0xFF5FE3B3)),
    ];

    final paint = Paint()..style = PaintingStyle.fill;
    for (var dot in dots) {
      double dotProgress = ((progress * 1.5) - (dot.delay * 0.5)).clamp(0.0, 1.0);
      if (dotProgress <= 0) continue;

      double eased = Curves.elasticOut.transform(dotProgress);
      double currentRadius = dot.radius * scale * eased;
      
      paint.color = dot.color.withOpacity(dotProgress);
      canvas.drawCircle(Offset(dot.x * scale, dot.y * scale), currentRadius, paint);
      
      if (dotProgress > 0.5) {
        double trailAlpha = (dotProgress - 0.5) * 2;
        final trailPaint = Paint()
          ..color = dot.color.withOpacity(0.2 * trailAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(
          Offset(dot.x * scale, (dot.y + 6) * scale),
          currentRadius * 0.9,
          trailPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => true;
}

class _Dot {
  final double x, y, radius, delay;
  final Color color;

  _Dot(this.x, this.y, this.radius, this.delay, this.color);
}
