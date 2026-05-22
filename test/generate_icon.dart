import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Generate App Icon PNG', (tester) async {
    final boundaryKey = GlobalKey();
    
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: CustomPaint(
                size: const Size(1024, 1024),
                painter: LogoPainterForExport(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final file = File('assets/app_icon_source.png');
    await file.writeAsBytes(buffer);
    print('SUCCESS: Icon generated at ${file.absolute.path}');
  });
}

// Copy of the painter logic from app_splash_screen.dart but with progress = 1.0
class LogoPainterForExport extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    double scale = size.width / 512;
    
    // Plate
    final platePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFDFCFB).withOpacity(0.95),
          const Color(0xFFE2D1C3).withOpacity(0.8),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 384 * scale, height: 384 * scale),
        Radius.circular(100 * scale),
      ),
      platePaint,
    );

    final dots = [
      _D(125, 170, 10, const Color(0xFF0B84FF)), _D(125, 206, 12, const Color(0xFF0B84FF)), _D(125, 242, 14, const Color(0xFF0B84FF)), _D(125, 278, 15, const Color(0xFF0B84FF)), _D(125, 314, 14, const Color(0xFF0B84FF)), _D(125, 350, 12, const Color(0xFF0B84FF)), _D(125, 386, 10, const Color(0xFF0B84FF)),
      _D(158, 190, 9, const Color(0xFF4256FF)), _D(158, 226, 11, const Color(0xFF4256FF)), _D(158, 262, 12, const Color(0xFF4256FF)), _D(158, 298, 11, const Color(0xFF4256FF)), _D(158, 334, 9, const Color(0xFF4256FF)), _D(158, 370, 7, const Color(0xFF4256FF)),
      _D(191, 210, 8, const Color(0xFF7A28FF)), _D(191, 246, 10, const Color(0xFF7A28FF)), _D(191, 282, 11, const Color(0xFF7A28FF)), _D(191, 318, 10, const Color(0xFF7A28FF)), _D(191, 354, 8, const Color(0xFF7A28FF)),
      _D(224, 230, 7, const Color(0xFFA100FF)), _D(224, 266, 9, const Color(0xFFA100FF)), _D(224, 302, 8, const Color(0xFFA100FF)), _D(224, 334, 6, const Color(0xFFA100FF)),
      _D(256, 250, 6, const Color(0xFFD000BD)), _D(256, 286, 8, const Color(0xFFD000BD)), _D(256, 322, 6, const Color(0xFFD000BD)),
      _D(288, 230, 7, const Color(0xFFFF007A)), _D(288, 266, 9, const Color(0xFFFF007A)), _D(288, 302, 8, const Color(0xFFFF007A)), _D(288, 334, 6, const Color(0xFFFF007A)),
      _D(321, 210, 8, const Color(0xFFD14B8D)), _D(321, 246, 10, const Color(0xFFD14B8D)), _D(321, 282, 11, const Color(0xFFD14B8D)), _D(321, 318, 10, const Color(0xFFD14B8D)), _D(321, 354, 8, const Color(0xFFD14B8D)),
      _D(354, 190, 9, const Color(0xFFA2979E)), _D(354, 226, 11, const Color(0xFFA2979E)), _D(354, 262, 12, const Color(0xFFA2979E)), _D(354, 298, 11, const Color(0xFFA2979E)), _D(354, 334, 9, const Color(0xFFA2979E)), _D(354, 370, 7, const Color(0xFFA2979E)),
      _D(387, 170, 10, const Color(0xFF5FE3B3)), _D(387, 206, 12, const Color(0xFF5FE3B3)), _D(387, 242, 14, const Color(0xFF5FE3B3)), _D(387, 278, 15, const Color(0xFF5FE3B3)), _D(387, 314, 14, const Color(0xFF5FE3B3)), _D(387, 350, 12, const Color(0xFF5FE3B3)), _D(387, 386, 10, const Color(0xFF5FE3B3)),
    ];

    for (var dot in dots) {
      paint.color = dot.color;
      canvas.drawCircle(Offset(dot.x * scale, dot.y * scale), dot.radius * scale, paint);
      // Removed trails and blur for headless test stability
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _D {
  final double x, y, radius;
  final Color color;
  _D(this.x, this.y, this.radius, this.color);
}
