import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/player_controller.dart';
import '../models/track_item.dart';
import '../services/album_art_dimensions.dart';
import 'track_album_art.dart';
import 'track_art_notifier.dart';

/// Library list artwork: deferred load while scrolling, single load per row, fade-in.
class TrackListAlbumArt extends StatefulWidget {
  const TrackListAlbumArt({
    super.key,
    required this.track,
    this.showShadow = true,
    this.cornerRadius,
  });

  final TrackItem track;
  final bool showShadow;
  final double? cornerRadius;

  @override
  State<TrackListAlbumArt> createState() => _TrackListAlbumArtState();
}

class _TrackListAlbumArtState extends State<TrackListAlbumArt> {
  final TrackArtNotifier _notifier = TrackArtNotifier();
  int? _pixelSize;

  int _listPixelSize(BuildContext context) {
    return (_size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(kAlbumArtMinDimension, kAlbumArtListMaxDimension);
  }

  static const double _size = 56;

  @override
  void didUpdateWidget(TrackListAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (trackArtPathKey(oldWidget.track) != trackArtPathKey(widget.track)) {
      _notifier.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadArt();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelSize ??= _listPixelSize(context);
    _maybeLoadArt();
  }

  void _maybeLoadArt() {
    if (!mounted) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) _maybeLoadArt();
      });
      return;
    }

    final player = PlayerController.of(context);
    final pixel = _pixelSize ?? _listPixelSize(context);
    final sync = _notifier.resolveSyncArt(widget.track, player, pixel);
    if (sync != null && sync.isNotEmpty) return;
    unawaited(_notifier.load(widget.track, player, maxDimension: pixel));
  }

  TrackItem _trackWithArt(Uint8List art) => widget.track.withEmbeddedMetadata(
        albumArtBytes: art,
        replaceAlbumArtFromFile: true,
      );

  @override
  void dispose() {
    _notifier.unbindArtAvailability();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.of(context);
    final pixel = _pixelSize ?? _listPixelSize(context);
    final syncArt = _notifier.resolveSyncArt(widget.track, player, pixel);

    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) {
        final art = _notifier.art ?? syncArt;
        if (art != null && art.isNotEmpty) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: TrackAlbumArt(
              key: ValueKey<String>('${trackArtPathKey(widget.track)}.loaded'),
              track: _trackWithArt(art),
              display: TrackArtDisplay.list,
              showShadow: widget.showShadow,
              cornerRadius: widget.cornerRadius,
            ),
          );
        }
        return TrackAlbumArt(
          key: ValueKey<String>('placeholder-${trackArtPathKey(widget.track)}'),
          track: widget.track,
          display: TrackArtDisplay.list,
          showShadow: widget.showShadow,
          cornerRadius: widget.cornerRadius,
        );
      },
    );
  }
}
