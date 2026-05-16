import '../models/track_item.dart';

import 'notification_art_uri_stub.dart'
    if (dart.library.io) 'notification_art_uri_io.dart' as impl;

/// `file://` URI for [MediaItem.artUri]: per-track cached 512×512 PNG that Android
/// can decode for the media notification (not a Flutter asset path). Web returns null.
Future<Uri?> uriForNotificationAlbumArt(TrackItem track) =>
    impl.uriForNotificationAlbumArt(track);
