/// Sub-pages inside the YouTube sidebar section (Library / Find).
enum YoutubePageId {
  library('library', 'Library'),
  find('find', 'Find'),
  bookmarks('bookmarks', 'Bookmarks');

  const YoutubePageId(this.wireValue, this.title);

  final String wireValue;
  final String title;

  static YoutubePageId? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in YoutubePageId.values) {
      if (v.wireValue == raw) return v;
    }
    return null;
  }
}
