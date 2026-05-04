/// Identifies a Library screen tab (persisted for playback origin + settings).
enum LibraryTabId {
  songs('songs', 'Songs'),
  recentlyAdded('recently_added', 'RecentlyAdded'),
  playlist('playlist', 'Playlist'),
  favourites('favourites', 'Favourites'),
  recentlyPlayed('recently_played', 'RecentlyPlayed');

  const LibraryTabId(this.wireValue, this.shortTitle);

  final String wireValue;
  final String shortTitle;

  static LibraryTabId? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in LibraryTabId.values) {
      if (v.wireValue == raw) return v;
    }
    return null;
  }
}
