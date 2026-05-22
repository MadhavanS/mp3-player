import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../theme/app_theme.dart';
import 'daisy_background.dart';

/// Where to show artwork: mini player, library row, full hero, compact now-playing.
enum TrackArtDisplay { mini, list, full, nowPlaying }

/// Embedded ID3 cover when [TrackItem.albumArtBytes] is set; otherwise gradient [TrackItem.artColors].
class TrackAlbumArt extends StatefulWidget {
  const TrackAlbumArt({
    super.key,
    required this.track,
    required this.display,
    this.showShadow = true,
    this.cornerRadius,
  });

  final TrackItem track;
  final TrackArtDisplay display;

  /// When false, skips drop shadow on the artwork (e.g. when wrapped in an outer card).
  final bool showShadow;

  /// When non-null, overrides the default corner radius for this [display] (use `0` for square art).
  final double? cornerRadius;

  @override
  State<TrackAlbumArt> createState() => _TrackAlbumArtState();
}

class _TrackAlbumArtState extends State<TrackAlbumArt> {
  Future<Uint8List?>? _artFuture;
  String? _artFutureKey;

  @override
  void didUpdateWidget(TrackAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pathChanged = oldWidget.track.filePath != widget.track.filePath;
    final oldLen = oldWidget.track.albumArtBytes?.length ?? 0;
    final newLen = widget.track.albumArtBytes?.length ?? 0;
    if (pathChanged || oldLen != newLen) {
      _artFutureKey = null;
      _artFuture = null;
    }
  }

  double get _size => switch (widget.display) {
    TrackArtDisplay.mini => 48,
    TrackArtDisplay.list => 56,
    TrackArtDisplay.full => 295,
    TrackArtDisplay.nowPlaying => 248,
  };

  double get _radius => switch (widget.display) {
    TrackArtDisplay.mini => 24,
    TrackArtDisplay.list => 14,
    TrackArtDisplay.full => 34,
    TrackArtDisplay.nowPlaying => 22,
  };

  double _radiusFor(BuildContext context) {
    if (!context.usesPlayerChrome) return _radius;
    return switch (widget.display) {
      TrackArtDisplay.mini => _radius,
      TrackArtDisplay.list => 18,
      TrackArtDisplay.full => 38,
      TrackArtDisplay.nowPlaying => 28,
    };
  }

  double _effectiveRadius(BuildContext context) {
    if (widget.display == TrackArtDisplay.mini) return _radiusFor(context);
    return widget.cornerRadius ?? _radiusFor(context);
  }

  Widget _noArtPlaceholder(BuildContext context) {
    if (context.appliedThemePalette == AppThemePalette.daisy) {
      return _daisyPlaceholderDecoration(context);
    }
    if (context.appliedThemePalette == AppThemePalette.silver) {
      return _silverPlaceholderDecoration(context);
    }
    if (context.appliedThemePalette == AppThemePalette.ivy) {
      return _ivyPlaceholderDecoration(context);
    }
    return _gradientDecoration(context);
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = widget.track.thumbnailUrl?.trim();
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      return _networkThumbnail(context, thumbUrl);
    }

    final bytes = widget.track.albumArtBytes;
    if (bytes == null || bytes.isEmpty) {
      return _noArtPlaceholder(context);
    }

    final pixelSize = (_size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 512)
        .toInt();
    final cached = cachedAlbumArtSync(widget.track, maxDimension: pixelSize);
    if (cached != null && cached.isNotEmpty) {
      return _imageShell(context, cached, pixelSize);
    }

    final futureKey =
        '${widget.track.filePath}|${bytes.length}|$pixelSize';
    if (_artFutureKey != futureKey) {
      _artFutureKey = futureKey;
      _artFuture = cachedAlbumArt(widget.track, maxDimension: pixelSize);
    }

    return FutureBuilder<Uint8List?>(
      future: _artFuture,
      builder: (context, snapshot) {
        final art = snapshot.data;
        if (art == null || art.isEmpty) {
          return _noArtPlaceholder(context);
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _imageShell(
            context,
            art,
            pixelSize,
            key: ValueKey<int>(identityHashCode(art)),
          ),
        );
      },
    );
  }

  Widget _networkThumbnail(BuildContext context, String url) {
    final pixelSize = (_size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 512)
        .toInt();
    final image = Image.network(
      url,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      cacheWidth: pixelSize,
      cacheHeight: pixelSize,
      errorBuilder: (_, __, ___) => _noArtPlaceholder(context),
    );
    if (widget.display == TrackArtDisplay.mini) {
      return ClipOval(
        child: SizedBox(width: _size, height: _size, child: image),
      );
    }
    final r = _effectiveRadius(context);
    final br = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: widget.showShadow ? _imageShadows() : const <BoxShadow>[],
      ),
      child: ClipRRect(borderRadius: br, child: image),
    );
  }

  Widget _imageShell(
    BuildContext context,
    Uint8List bytes,
    int pixelSize, {
    Key? key,
  }) {
    final r = _effectiveRadius(context);
    final image = Image.memory(
      bytes,
      key: key,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      cacheWidth: pixelSize,
      cacheHeight: pixelSize,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _noArtPlaceholder(context),
    );

    if (widget.display == TrackArtDisplay.mini) {
      return ClipOval(
        child: SizedBox(width: _size, height: _size, child: image),
      );
    }
    final br = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: widget.showShadow ? _imageShadows() : const <BoxShadow>[],
      ),
      child: ClipRRect(borderRadius: br, child: image),
    );
  }

  List<BoxShadow> _imageShadows() => switch (widget.display) {
    TrackArtDisplay.full => [
      BoxShadow(
        color: Colors.black.withOpacity(0.12),
        blurRadius: 28,
        offset: const Offset(0, 18),
      ),
    ],
    TrackArtDisplay.nowPlaying => [
      BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
    _ => const [],
  };

  /// Silver: flat neutral tile instead of [track.artColors] gradient when there is no cover.
  Widget _silverPlaceholderDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final brNonMini = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    const fill = Color(0xFFB8B4AE);
    const fillTop = Color(0xFFC4C0BA);
    const placeholderBorder = Border.fromBorderSide(
      BorderSide(color: Color(0xFF0A0A0A), width: 1.75),
    );
    final deco = BoxDecoration(
      border: placeholderBorder,
      borderRadius: widget.display == TrackArtDisplay.mini
          ? null
          : brNonMini,
      shape: widget.display == TrackArtDisplay.mini
          ? BoxShape.circle
          : BoxShape.rectangle,
      gradient: widget.display == TrackArtDisplay.mini
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [fillTop, fill],
            ),
      color: widget.display == TrackArtDisplay.mini ? fill : null,
      boxShadow: widget.showShadow
          ? switch (widget.display) {
              TrackArtDisplay.mini => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              TrackArtDisplay.list => const [],
              TrackArtDisplay.full => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              TrackArtDisplay.nowPlaying => [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
            }
          : const <BoxShadow>[],
    );

    return Container(width: _size, height: _size, decoration: deco);
  }

  Widget _gradientDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final brNonMini = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    final gradient = BoxDecoration(
      borderRadius: widget.display == TrackArtDisplay.mini
          ? null
          : brNonMini,
      shape: widget.display == TrackArtDisplay.mini
          ? BoxShape.circle
          : BoxShape.rectangle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: widget.track.artColors,
      ),
      boxShadow: widget.showShadow
          ? switch (widget.display) {
              TrackArtDisplay.mini => [
                BoxShadow(
                  color: widget.track.artColors.first.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              TrackArtDisplay.list => const [],
              TrackArtDisplay.full => [
                BoxShadow(
                  color: widget.track.artColors.last.withOpacity(0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
              TrackArtDisplay.nowPlaying => [
                BoxShadow(
                  color: widget.track.artColors.last.withOpacity(0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            }
          : const <BoxShadow>[],
    );

    return Container(width: _size, height: _size, decoration: gradient);
  }

  Widget _daisyPlaceholderDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final br = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    final isMini = widget.display == TrackArtDisplay.mini;
    final shape = isMini ? BoxShape.circle : BoxShape.rectangle;
    final outline = Border.all(
      color: const Color(0xFF2B2117).withValues(alpha: 0.9),
      width: 1.5,
    );

    final List<BoxShadow> boxShadows = widget.showShadow
        ? switch (widget.display) {
            TrackArtDisplay.mini => [
                BoxShadow(
                  color: const Color(0xFF2B2117).withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            TrackArtDisplay.list => const [],
            TrackArtDisplay.full => [
                BoxShadow(
                  color: const Color(0xFF2B2117).withValues(alpha: 0.14),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            TrackArtDisplay.nowPlaying => [
                BoxShadow(
                  color: const Color(0xFF2B2117).withValues(alpha: 0.11),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
          }
        : const <BoxShadow>[];

    final shell = BoxDecoration(
      shape: shape,
      borderRadius: isMini ? null : br,
      border: outline,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE5D8C4), Color(0xFFD3C0A7)],
      ),
      boxShadow: boxShadows,
    );

    return Container(
      width: _size,
      height: _size,
      decoration: shell,
      child: ClipRRect(
        borderRadius: isMini ? BorderRadius.circular(_size) : br,
        child: Opacity(
          opacity: 0.56,
          child: Image.asset(
            daisyTextureAssetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// Ivy: frosted glass tile with soft neutral rim.
  Widget _ivyPlaceholderDecoration(BuildContext context) {
    final r = _effectiveRadius(context);
    final br = r <= 0 ? BorderRadius.zero : BorderRadius.circular(r);
    final isMini = widget.display == TrackArtDisplay.mini;
    final shape = isMini ? BoxShape.circle : BoxShape.rectangle;
    final outline = Border.all(
      color: Colors.white.withValues(alpha: 0.72),
      width: 1.2,
    );

    final List<BoxShadow> boxShadows = widget.showShadow
        ? switch (widget.display) {
            TrackArtDisplay.mini => [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            TrackArtDisplay.list => const [],
            TrackArtDisplay.full => [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            TrackArtDisplay.nowPlaying => [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 9),
                ),
              ],
          }
        : const <BoxShadow>[];

    final deco = BoxDecoration(
      shape: shape,
      borderRadius: isMini ? null : br,
      border: outline,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.82),
          const Color(0xFFF2F2F5).withValues(alpha: 0.38),
        ],
      ),
      boxShadow: boxShadows,
    );

    return Container(width: _size, height: _size, decoration: deco);
  }
}
