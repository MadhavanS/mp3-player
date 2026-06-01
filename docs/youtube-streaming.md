# YouTube streaming (feat/youtube-stream-live)

## Navigation (done)

- **Menu › YouTube** — dedicated hub with **Library** (downloads) and **Find** (search).
- Find search text is persisted and kept while switching sub-tabs (`AutomaticKeepAliveClientMixin`).
- **Settings › YouTube › Default page** — Library or Find on open.

## Playback phases

### Phase 1 (current)

- `YoutubeStreamResolver` — manifest + URL cache (extends explode clients).
- `YoutubePlaybackResolver` — local file first; stream URI wiring next.

### Phase 2

- `AudioSource.uri` + headers, invalidate on 403, retry with client rotation.

### Phase 3

- Temp-file progressive buffer only if direct URI fails on target devices.
