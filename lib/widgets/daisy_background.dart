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
    if (!daisy && !leah) {
      return ColoredBox(color: baseColor, child: child);
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
