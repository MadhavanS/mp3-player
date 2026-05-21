import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Themed seek / volume slider used across the app.
///
/// Set [appearance] to [PlayerSliderAppearance.miniPill] for the mini player.
class PlayerAdaptiveSlider extends StatelessWidget {
  const PlayerAdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.appearance = PlayerSliderAppearance.softBlur,
    this.padding = EdgeInsets.zero,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final PlayerSliderAppearance appearance;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? context.controlAccent;
    final thumb = thumbColor ?? accent;

    return SliderTheme(
      data: _materialSliderTheme(context, accent: accent, thumb: thumb),
      child: Slider(
        padding: padding,
        value: value.clamp(min, max),
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
      ),
    );
  }

  SliderThemeData _materialSliderTheme(
    BuildContext context, {
    required Color accent,
    required Color thumb,
  }) {
    final base = SliderTheme.of(context);
    switch (appearance) {
      case PlayerSliderAppearance.ivy:
        return base.copyWith(
          trackHeight: _IvyLiquidGlassTrackShape.trackHeight,
          trackShape: const _IvyLiquidGlassTrackShape(),
          thumbShape: const _IvyLiquidGlassThumbShape(),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: accent,
          inactiveTrackColor: Colors.transparent,
          thumbColor: Colors.transparent,
          padding: EdgeInsets.zero,
        );
      case PlayerSliderAppearance.silver:
        return base.copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: const Color(0xFF1C1C1E),
          inactiveTrackColor:
              inactiveColor ?? const Color(0xFF1C1C1E).withValues(alpha: 0.22),
          thumbColor: const Color(0xFF1C1C1E),
          padding: EdgeInsets.zero,
        );
      case PlayerSliderAppearance.daisy:
      case PlayerSliderAppearance.accentOnly:
        return base.copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: accent,
          inactiveTrackColor:
              inactiveColor ?? accent.withValues(alpha: 0.35),
          thumbColor: thumb,
          padding: EdgeInsets.zero,
        );
      case PlayerSliderAppearance.softBlur:
        return base.copyWith(
          trackHeight: 3,
          thumbShape: _SoftBlurSeekThumbShape(color: thumb),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: accent,
          inactiveTrackColor:
              inactiveColor ?? accent.withValues(alpha: 0.28),
          thumbColor: thumb,
          padding: EdgeInsets.zero,
        );
      case PlayerSliderAppearance.miniPill:
        return base.copyWith(
          trackHeight: 3,
          thumbShape: _MiniPlayerPillThumbShape(color: thumb),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: accent,
          inactiveTrackColor: inactiveColor ?? accent.withValues(alpha: 0.32),
          thumbColor: thumb,
          padding: EdgeInsets.zero,
        );
      case PlayerSliderAppearance.nebula:
        return base.copyWith(
          trackHeight: 11,
          trackShape: const _NebulaTrackShape(),
          thumbShape: const _NebulaThumbShape(),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: accent,
          inactiveTrackColor: Colors.transparent,
          thumbColor: thumb,
          padding: EdgeInsets.zero,
        );
    }
  }
}

enum PlayerSliderAppearance {
  softBlur,
  ivy,
  silver,
  daisy,
  accentOnly,
  miniPill,
  nebula,
}

/// Platform-styled switch ([Switch.adaptive]) with theme accent.
class PlayerAdaptiveSwitch extends StatelessWidget {
  const PlayerAdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final active = activeColor ?? context.controlAccent;
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: active,
    );
  }
}

/// Confirm / cancel dialog with destructive styling when needed.
Future<bool?> showPlayerConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'OK',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// Pill thumb for mini-player seek bar.
final class _MiniPlayerPillThumbShape extends SliderComponentShape {
  const _MiniPlayerPillThumbShape({required this.color});

  final Color color;

  static const double width = 12;
  static const double height = 6;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    context.canvas.drawRRect(
      RRect.fromRectXY(rect, 3, 3),
      Paint()..color = color,
    );
  }
}

/// Soft vertical tick for Julia / Leah now-playing seek.
final class _SoftBlurSeekThumbShape extends SliderComponentShape {
  const _SoftBlurSeekThumbShape({required this.color});

  final Color color;
  static const double _w = 3;
  static const double _h = 14;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(_w, _h);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final t = enableAnimation.value;
    final c = Color.lerp(color.withValues(alpha: 0.4), color, t)!;
    final rect = Rect.fromCenter(center: center, width: _w, height: _h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(0.5));
    context.canvas.drawRRect(rrect, Paint()..color = c);
  }
}

/// Sunken frosted capsule track for Ivy liquid-glass sliders.
final class _IvyLiquidGlassTrackShape extends SliderTrackShape {
  const _IvyLiquidGlassTrackShape();

  static const double trackHeight = 7;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(trackLeft, trackTop, parentBox.size.width, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    required TextDirection textDirection,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.width <= 0) return;

    final t = enableAnimation.value;
    final radius = Radius.circular(trackRect.height / 2);
    final trackRrect = RRect.fromRectAndRadius(trackRect, radius);

    // Inactive track: Soft grey sunken slot
    canvas.drawRRect(
      trackRrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFD1D1D6).withValues(alpha: 0.45 * t + 0.1),
            const Color(0xFFE5E5EA).withValues(alpha: 0.35 * t + 0.05),
          ],
        ).createShader(trackRect),
    );

    final activeLeft = switch (textDirection) {
      TextDirection.rtl => thumbCenter.dx,
      TextDirection.ltr => trackRect.left,
    };
    final activeRight = switch (textDirection) {
      TextDirection.rtl => trackRect.right,
      TextDirection.ltr => thumbCenter.dx,
    };

    if (activeRight > activeLeft) {
      final activeRect = Rect.fromLTRB(
        activeLeft,
        trackRect.top,
        activeRight.clamp(trackRect.left, trackRect.right),
        trackRect.bottom,
      );
      
      final accent = sliderTheme.activeTrackColor ?? const Color(0xFF007AFF);
      final activeRrect = RRect.fromRectAndCorners(
        activeRect,
        topLeft: textDirection == TextDirection.ltr ? radius : Radius.zero,
        bottomLeft: textDirection == TextDirection.ltr ? radius : Radius.zero,
        topRight: textDirection == TextDirection.rtl ? radius : Radius.zero,
        bottomRight: textDirection == TextDirection.rtl ? radius : Radius.zero,
      );

      // Active track: Vibrant blue with subtle top sheen
      canvas.drawRRect(
        activeRrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.95 * t),
              accent.withValues(alpha: 0.85 * t),
            ],
          ).createShader(activeRect),
      );

      canvas.drawRRect(
        activeRrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.2),
            colors: [
              Colors.white.withValues(alpha: 0.35 * t),
              Colors.transparent,
            ],
          ).createShader(activeRect),
      );
    }
  }
}

/// Wide horizontal pill thumb with liquid glass effect.
final class _IvyLiquidGlassThumbShape extends SliderComponentShape {
  const _IvyLiquidGlassThumbShape();

  static const double width = 42;
  static const double height = 26;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final t = enableAnimation.value;
    final act = activationAnimation.value;
    
    final rect = Rect.fromCenter(
      center: center,
      width: width + 4 * act,
      height: height + 2 * act,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );

    // Deep soft shadow for the glass "drop"
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Main glass body
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.92 * t),
            Colors.white.withValues(alpha: 0.45 * t),
            Colors.white.withValues(alpha: 0.65 * t),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // Refracted/Brightened track segment inside the glass
    final accent = sliderTheme.activeTrackColor ?? const Color(0xFF007AFF);
    final trackH = _IvyLiquidGlassTrackShape.trackHeight;
    final innerTrackRect = Rect.fromCenter(
      center: center,
      width: width * 0.7,
      height: trackH,
    );
    
    // We only draw the refracted part of the track if it's logically "under" the thumb
    // (though in this specific style, it looks like a permanent core)
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerTrackRect, Radius.circular(trackH / 2)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0.95),
            Color.lerp(accent, Colors.white, 0.4)!,
          ],
        ).createShader(innerTrackRect),
    );

    // Top specular highlight (sharp)
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-0.8, -1.0),
          end: const Alignment(0.4, 0.2),
          colors: [
            Colors.white.withValues(alpha: 0.75 * t),
            Colors.transparent,
          ],
          stops: const [0.0, 0.8],
        ).createShader(rect),
    );

    // Glass edge stroke
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.85 * t),
            Colors.white.withValues(alpha: 0.15 * t),
          ],
        ).createShader(rect),
    );
  }
}

/// Thick nebula track with deep-space gradient and subtle glow.
final class _NebulaTrackShape extends SliderTrackShape {
  const _NebulaTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 11;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(trackLeft, trackTop, parentBox.size.width, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    required TextDirection textDirection,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.width <= 0) return;

    final t = enableAnimation.value;
    final radius = Radius.circular(trackRect.height / 2);
    final trackRrect = RRect.fromRectAndRadius(trackRect, radius);

    // Background track (deep dark space)
    canvas.drawRRect(
      trackRrect,
      Paint()..color = const Color(0xFF0D0D12).withValues(alpha: 0.4 * t + 0.2),
    );

    final activeLeft = textDirection == TextDirection.ltr ? trackRect.left : thumbCenter.dx;
    final activeRight = textDirection == TextDirection.ltr ? thumbCenter.dx : trackRect.right;

    if (activeRight > activeLeft) {
      final activeRect = Rect.fromLTRB(activeLeft, trackRect.top, activeRight, trackRect.bottom);
      final activeRrect = RRect.fromRectAndRadius(activeRect, radius);
      final accent = sliderTheme.activeTrackColor ?? const Color(0xFF007AFF);

      // Main active gradient
      canvas.drawRRect(
        activeRrect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              accent.withValues(alpha: 0.8),
              Color.lerp(accent, Colors.white, 0.35)!,
            ],
          ).createShader(activeRect),
      );

      // Subtle glow
      canvas.drawRRect(
        activeRrect,
        Paint()
          ..color = accent.withValues(alpha: 0.3 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }
}

/// Circular glowing thumb for Nebula slider.
final class _NebulaThumbShape extends SliderComponentShape {
  const _NebulaThumbShape();

  static const double _radius = 9;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_radius * 2, _radius * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final t = enableAnimation.value;
    final accent = sliderTheme.thumbColor ?? Colors.white;

    // Outer glow
    canvas.drawCircle(
      center,
      _radius + 4 * activationAnimation.value,
      Paint()
        ..color = accent.withValues(alpha: 0.35 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Inner glow / body
    canvas.drawCircle(
      center,
      _radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            accent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: _radius)),
    );
  }
}
