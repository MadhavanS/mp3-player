/// True when [query] is a channel browse request (`@channel` or `@channel name`).
bool isYoutubeChannelSearchQuery(String query) {
  return query.trim().startsWith('@');
}

/// Channel name or handle after the leading `@`.
String youtubeChannelNameFromQuery(String query) {
  return query.trim().substring(1).trim();
}
