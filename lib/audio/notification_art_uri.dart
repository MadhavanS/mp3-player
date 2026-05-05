import '../models/track_item.dart';

import 'notification_art_uri_stub.dart'
    if (dart.library.io) 'notification_art_uri_io.dart' as impl;

/// File URI for [MediaItem.artUri] where the platform loads notification artwork
/// (writes embedded tag bytes to cache). Web returns null.
Future<Uri?> uriForNotificationAlbumArt(TrackItem track) =>
    impl.uriForNotificationAlbumArt(track);
