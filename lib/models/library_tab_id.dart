/// Identifies a Library screen tab (persisted for playback origin + settings).
enum LibraryTabId {
  songs('songs', 'Songs'),
  /// Active playback queue (order matches what will play next, including shuffle).
  nowPlayingList('now_playing_list', 'Queue'),
  recentlyAdded('recently_added', 'RecentlyAdded'),
  playlist('playlist', 'Playlist'),
  favourites('favourites', 'Favourites'),
  recentlyPlayed('recently_played', 'RecentlyPlayed'),
  savedYoutubeAudio('saved_youtube_audio', 'Saved audio'),
  savedYoutubeLinks('saved_youtube_links', 'Saved links'),
  youtubeDownloads('youtube_downloads', 'Downloads'),

  /// Playback started from Online search (not a library tab).
  onlineSearch('online_search', 'Online search');

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
