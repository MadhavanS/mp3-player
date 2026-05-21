import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'liquid_glass.dart';

/// Root [Navigator] — assign to [MaterialApp.navigatorKey] so overlays can show
/// after modal routes ([showModalBottomSheet], dialogs) dispose their context.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Short pill near the bottom of the screen, above bottom chrome (mini player, now playing
/// footer) with theme-aware default colors.
/// Replaces overlapping previous pill if invoked again immediately.
abstract final class ActionPillToast {
  static ({Color bg, Color fg}) _pillColorsFor(BuildContext context) {
    final applied = context.appliedThemePalette;
    if (applied == AppThemePalette.silver) {
      return (bg: const Color(0xFFC8C8C8), fg: const Color(0xFF0A0A0A));
    }
    if (applied == AppThemePalette.daisy) {
      return (bg: const Color(0xFFCAB89E), fg: const Color(0xFF0A0A0A));
    }
    if (applied == AppThemePalette.ivy) {
      return (bg: Colors.transparent, fg: const Color(0xFF1C1C1E));
    }
    final bg = context.controlAccent;
    if (applied == AppThemePalette.leah) {
      return (bg: bg, fg: const Color(0xFF0A0A0A));
    }
    final fg = bg.computeLuminance() > 0.45
        ? const Color(0xFF0A0A0A)
        : Colors.white;
    return (bg: bg, fg: fg);
  }

  ActionPillToast._();

  /// Clears typical bottom bars (now playing tools row, collapsed-player strip) plus a gap.
  /// Used for themes that do not use a tighter pill offset (see [_themeAwareBottomInset]).
  static const double _aboveBottomChrome = 88;

  /// Same vertical offset as shuffle / repeat / favourite pills on Now Playing.
  static double _themeAwareBottomInset(BuildContext context) {
    switch (context.appliedThemePalette) {
      case AppThemePalette.silver:
        return 54;
      case AppThemePalette.julia:
        return 64;
      case AppThemePalette.leah:
        return 175;
      case AppThemePalette.ivy:
        return 175;
      case AppThemePalette.light:
      case AppThemePalette.dark:
      case AppThemePalette.grey:
      case AppThemePalette.daisy:
        return _aboveBottomChrome;
    }
  }

  static OverlayEntry? _current;
  static Timer? _dismissTimer;

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final entry = _current;
    _current = null;
    if (entry == null) return;
    if (!entry.mounted) return;
    try {
      entry.remove();
    } catch (_) {
      // Guard against rare double-remove races during rapid toast replacement.
    }
  }

  static String _effectiveLabel(String message, bool uppercaseLabel) {
    final t = message.trim();
    if (t.isEmpty) return '';
    return uppercaseLabel ? t.toUpperCase() : t;
  }

  /// Uses [uppercaseLabel] true for dense “toast” captions (matches reference UI).
  static void show(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_rounded,
    bool uppercaseLabel = false,
    Duration dwell = const Duration(milliseconds: 2400),
    double? bottomInsetFromSafeArea,
  }) {
    final label = _effectiveLabel(message, uppercaseLabel);
    if (label.isEmpty) return;

    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ??
            appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final themeData = Theme.of(context);
    final colors = _pillColorsFor(context);
    final pillBg = colors.bg;
    final pillFg = colors.fg;
    final ivyPill = context.appliedThemePalette == AppThemePalette.ivy;

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final bottom =
            MediaQuery.viewPaddingOf(ctx).bottom +
            (bottomInsetFromSafeArea ?? _themeAwareBottomInset(context));
        final textStyle = themeData.textTheme.labelSmall?.copyWith(
          color: pillFg,
          fontWeight: FontWeight.w800,
          letterSpacing: uppercaseLabel ? 0.85 : 0.35,
          fontSize: uppercaseLabel ? 11 : 12,
        );

        final pillContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: pillFg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ),
          ],
        );

        return Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom, left: 24, right: 24),
              child: IgnorePointer(
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: ivyPill
                        ? LiquidGlassSurface(
                            borderRadius: BorderRadius.circular(24),
                            style: BackdropGlassStyle.card,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: pillContent,
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: pillContent,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _current = entry;

    _dismissTimer = Timer(dwell, () {
      // Only the currently visible toast may dismiss itself.
      if (!identical(_current, entry)) return;
      dismiss();
    });
  }

  /// After popping a modal, the sheet context is unmounted; use navigator key context.
  static void showUsingRootNavigator(
    String message, {
    IconData icon = Icons.check_rounded,
    bool uppercaseLabel = false,
    Duration dwell = const Duration(milliseconds: 2400),
    double? bottomInsetFromSafeArea,
  }) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    show(
      ctx,
      message,
      icon: icon,
      uppercaseLabel: uppercaseLabel,
      dwell: dwell,
      bottomInsetFromSafeArea: bottomInsetFromSafeArea,
    );
  }
}
