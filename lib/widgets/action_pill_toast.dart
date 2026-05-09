import 'dart:async';

import 'package:flutter/material.dart';

/// Root [Navigator] — assign to [MaterialApp.navigatorKey] so overlays can show
/// after modal routes ([showModalBottomSheet], dialogs) dispose their context.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Short pill near the bottom of the screen, above bottom chrome (mini player, now playing
/// footer) — neutral gray pill, black label and icon.
/// Replaces overlapping previous pill if invoked again immediately.
abstract final class ActionPillToast {
  ActionPillToast._();

  /// Clears typical bottom bars (now playing tools row, collapsed-player strip) plus a gap.
  static const double _aboveBottomChrome = 88;

  static OverlayEntry? _current;

  static void dismiss() {
    _current?.remove();
    _current = null;
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
  }) {
    final label = _effectiveLabel(message, uppercaseLabel);
    if (label.isEmpty) return;

    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ??
            appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final themeData = Theme.of(context);
    const pillBg = Color(0xFFC8C8C8);
    const pillFg = Color(0xFF0A0A0A);

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final bottom =
            MediaQuery.viewPaddingOf(ctx).bottom + _aboveBottomChrome;
        final textStyle = themeData.textTheme.labelSmall?.copyWith(
          color: pillFg,
          fontWeight: FontWeight.w800,
          letterSpacing: uppercaseLabel ? 0.85 : 0.35,
          fontSize: uppercaseLabel ? 11 : 12,
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
                    child: DecoratedBox(
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
                        child: Row(
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
                        ),
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

    unawaited(
      Future<void>.delayed(dwell, () {
        // [dismiss]/a newer toast may already have removed [entry]; removing twice asserts.
        if (!entry.mounted) {
          if (identical(_current, entry)) _current = null;
          return;
        }
        entry.remove();
        if (identical(_current, entry)) _current = null;
      }),
    );
  }

  /// After popping a modal, the sheet context is unmounted; use navigator key context.
  static void showUsingRootNavigator(
    String message, {
    IconData icon = Icons.check_rounded,
    bool uppercaseLabel = false,
    Duration dwell = const Duration(milliseconds: 2400),
  }) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    show(
      ctx,
      message,
      icon: icon,
      uppercaseLabel: uppercaseLabel,
      dwell: dwell,
    );
  }
}
