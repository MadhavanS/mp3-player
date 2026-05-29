# MadPlayer — architecture notes

Living document for playback, library, metadata, and Android widget behavior.  
Update this when you change `PlayerController`, catalog sync, or home-screen widgets.

---

## Project layout (actual)

```
lib/
  main.dart, app.dart              # App shell, theme, Android widget sync
  audio/
    player_controller.dart         # Playback coordinator (not a ChangeNotifier)
    player_notifiers.dart          # position / track / playback / queue notifiers
    library_catalog.dart           # Full-library index (tags only, no embedded art)
    album_art_resolver.dart        # Unified cover bytes (hot → disk → embedded)
    art_availability_notifier.dart # Broadcast when a path gains cached art
  features/
    library/                       # Songs tab, Files explorer, queue tab
    player/                        # Now playing, mini player
    shell/                         # Main shell, folder scan, background sync
  services/
    library_track_sort.dart        # Shared sort modes (Songs + Files)
    track_grouping.dart            # Reusable group resolvers (album now, artist-ready)
    song_metadata_cache_io.dart    # Isar tag cache (fingerprints, no art bytes)
    album_art_cache_io.dart        # Path-keyed PNG disk cache for list art
    track_metadata_io.dart         # metadata_god → Dart fallback reads
  platform/
    android_home_widget_bridge.dart
android/.../Mp3Player*.kt           # Home widgets + MethodChannel sync
```

---

## Playback: `ConcatenatingAudioSource`

**Platform:** Android (and non-Windows targets) use one `AudioPlayer` with a single  
`ConcatenatingAudioSource` (`useLazyPreparation: true` on Android). Only the current  
track and immediate neighbors are prepared — not the entire library at once.

**Windows:** `just_audio_windows` is unreliable with concat + `initialIndex`, so each  
navigation reloads a **single** `AudioSource.uri` for the current track only.

### Fast path (normal skip)

```
skipNext() / skipPrevious()
  → update Dart _index (or shuffle position)
  → _seekToPlaylistIndexFast()
  → player.seek(Duration.zero, index: concatIndex)   // same concat, no decoder teardown
```

### Full reload (`_loadCurrent` → `setAudioSource`)

Used when the native child list must be rebuilt:

| Trigger | Notes |
|--------|--------|
| `setPlaylist` / `setPlaylistAndPlay` / `jumpToIndex` | New queue or start index |
| `tryResyncQueueWithLibraryScan` | Full library queue replaced |
| `_sourceNeedsReload == true` | Reorder, shuffle toggle, failed in-place mutation, scope change |
| Current track path change | `replaceTrackPath` while playing |
| `removePlaylistEntryAt` when current row removed | |
| Windows | Every skip uses reload |

### In-place concat mutation (`_concatSource`)

`PlayerController` keeps a reference to the live `ConcatenatingAudioSource` after  
`_loadCurrent()` and updates **`_activeSourceOrder`** (playlist index per concat child).

| Operation | In-place when possible | Fallback |
|-----------|------------------------|----------|
| `appendToPlaylist` (queue not empty) | `addAll()` | `_loadCurrent()` |
| `playTrackNext` (no shuffle) | `insert()` after current | `_sourceNeedsReload` |
| `removePlaylistEntryAt` (not current) | `removeAt()` | `_loadCurrent()` |

**Guards:** `_canMutateConcatInPlace` — not Windows, `_concatSource != null`,  
not loading, not `_sourceNeedsReload`.

### Large queues

Building thousands of `AudioSource` children runs on the main isolate with a  
**yield every 64 tracks** (`Future.delayed(Duration.zero)`) to avoid long UI freezes.  
Notification art URIs are resolved lazily after load (`_scheduleNotificationArtRefresh`),  
not during concat child construction.

### Shuffle

- Dart owns shuffle order: `_shuffleOrder`, `_shufflePos`, `_index`.
- **`toggleShuffle()`** sets **`_sourceNeedsReload = true`** so the next skip/reload  
  rebuilds concat children in the new order (native order is not updated immediately).
- Does **not** use `AudioPlayer.setShuffleModeEnabled` — that would conflict with  
  folder scope and custom queue semantics.

### Repeat modes (`PlaylistRepeatMode`)

| Mode | Behavior |
|------|----------|
| `off` | End of queue → pause (`skipNext` at end) |
| `all` | Wrap in scoped/shuffle order |
| `one` | Intercept concat **auto-advance** in `_onConcatIndexChanged`; seek to  
  current concat index at 0 and replay. Also handled in `_handleTrackCompleted`.  
  Deduped via `_scheduleRepeatOneReplay`. |

Concat advances to the next child **before** `ProcessingState.completed` on some  
platforms — repeat-one must not rely on completion alone.

### Sleep timer (end of song)

Same auto-advance issue as repeat-one: intercept in `_onConcatIndexChanged`, pause,  
seek to end of current child, do not start the next track.

### `_playbackPausedByUser` vs `stop()` during load

`playerStateStream` must **not** treat `playing: false` from `_loadCurrent()`'s `stop()` as a  
user pause. That blocked `_resumePlaybackAfterLoad` (tap track → silence).

Guards:

- Ignore while `_isLoadingSource`, `_manualQueueAdvance`, or **`_transportPauseGuardDepth > 0`**
  (`_guardedTransport` wraps `setPlaylistAndPlay`, load+play paths).
- `_resumePlaybackAfterLoad` clears `_playbackPausedByUser` at entry (callers intend to play).
- **`AudioSession.setActive(true)`** before `play()` on Android/iOS (session init is awaited).

---

## Player UI state (split notifiers)

`PlayerController` is **not** a `ChangeNotifier`. UI listens to narrow notifiers:

| Notifier | Fires on | Typical UI |
|----------|----------|------------|
| `positionNotifier` | Position/duration ~500 ms | Seek bars (mini + now playing) |
| `track` | Current track, metadata enrichment | Title, art, play icon on row |
| `playback` | Play/pause, processing (coalesced) | Transport buttons |
| `queue` | Playlist, shuffle, repeat, catalog | Queue tab, skip availability |

**Helpers on controller:**

- `playbackListenable`, `queueListenable`, `trackAndQueueListenable`  
  (`canSkipNext` needs track + queue).
- `uiListenable` — merge of track + playback + queue (**avoid for new UI**;  
  rebuilds too much).

**`PlayerControllerScope`** (InheritedWidget) exposes `of(context)` and  
`positionOf` / `trackOf` / etc.

### UI rebuild guidelines

| Widget concern | Listen to |
|----------------|-----------|
| Seek bar | `positionNotifier` only — not `audioPlayer.positionStream` |
| Play/pause | `playback` |
| Next enabled | `trackAndQueueListenable` or `track` + `queue` |
| Now-playing row highlight (library) | `track` per row via `_TrackTile` + `highlightWhenCurrent` — not `queue` |
| Library list data | `queue` (catalog size/order only); scope `ListenableBuilder` to tab body |
| Path → row lookup | `libraryTracksByPathKey()` once per rebuild — not `_trackForPath` in `itemBuilder` |
| Playback queue storage | `_playlistPaths` (strings); `playlist` getter resolves tags from catalog |

---

## Library & metadata

### Two layers

1. **`LibraryCatalog`** — full disk library for Songs tab (paths + tags, **no**  
   `albumArtBytes` in catalog rows). Art: disk cache + small RAM LRU (`_artHot`).
2. **`PlayerController._playlist`** — current playback queue (may be favourites,  
   user playlist, or full library subset).

### Persistence & sync

- **Isar `SongMetadataCache` (v4 DB):** tags + `fileModifiedMs` + **`fileSizeBytes`** for  
  change detection; **`hasArtDiskCache`** + fingerprint fields for path-keyed PNG art  
  (`isArtCacheValid` when mtime/size match). Startup prefill uses Isar only (no cache-dir scan).  
  One-time backfill maps existing disk PNGs into flags after upgrade.
- **Disk art cache:** `album_art_cache_io.dart` — PNG per path key and dimension  
  (`path_<hash>_512.png`, etc.). Metadata reads prime **512** by default; list/mini  
  request device-sized thumbs (~168–224px).
- **Any-dimension read:** `cachedAlbumArtForPathAnyDimension` tries 512 → 256 → 192 → 128  
  and resizes in memory so play/warmup at 512 still fills list rows at 192.
- **Unified resolver:** `resolveAlbumArtBytes` / `resolveAlbumArtBytesSync` in  
  `album_art_resolver.dart` — hot LRU → any disk size → embedded bytes. Used by  
  `TrackListAlbumArt`, `TrackAlbumArt` (mini/NP), notification refresh, home widget.
- **Art availability:** `PlayerController.artAvailability` — `markAlbumArtAvailable`  
  after disk/hot updates; list `TrackArtNotifier` subscribes and retries loads.
- **List rows:** `TrackListAlbumArt` + `TrackArtNotifier` (deferred scroll, no file read  
  in notifier; visible-row enrich in `library_screen._enrichVisibleSongsArt` calls  
  `readAudioMetadata` + `updateTrackByPath`).
- **Current-track UI:** `updateTrackByPath` calls `_notifyTrack()` when art lands for the  
  playing path so mini player rebuilds; notification uses debounced retry while loading.
- **Notification / widget:** `uriForNotificationAlbumArt` falls back to path disk cache  
  before rasterizing a gradient placeholder; widget sync in `app.dart` uses the resolver.
- **Startup:** restore Isar → background sync only **changed** files (when fingerprints OK) →  
  `prefillArtAvailabilityFromDiskCache` (Isar `hasArtDiskCache` query) + art warmup (cover-only).
- **Folder add:** scan + enrich; idle rescan may run later.
- **Rename/delete:** `evictArtCachesForPath` clears path disk art, notification art cache, hot LRU, and `artAvailability` for the old path.
- **Art warmup:** cover-only `readCoverBytesOnly` (tags already in Isar); continues at 300ms/item while playing instead of pausing entirely.

### Album art pipeline

```
readAudioMetadata / play enrich
  → primeAlbumArtDiskCache (512 PNG under album_art_cache/)
  → LibraryCatalog hot LRU + markAlbumArtAvailable(pathKey)

UI resolveAlbumArtBytes(targetDimension)
  → hot LRU
  → cachedAlbumArtForPathAnyDimension (512|256|192|128, resize if needed)
  → TrackItem.albumArtBytes
  → placeholder

Surfaces: TrackListAlbumArt | TrackAlbumArt | notification | home widget
```

### Metadata backends

- Default: `audio_metadata_reader`
- Optional: `metadata_god` (Rust) with Dart fallback — see README for Windows build policy.
- `metadata_backend_config.dart` / `--dart-define=USE_METADATA_GOD`

### Refresh without stopping playback

- `refreshLibraryDuringPlayback` — update in-memory tags only, no `setAudioSource`.
- `tryResyncQueueWithLibraryScan` — replace queue when origin is Songs library.

---

## Library sort

Defined in `lib/services/library_track_sort.dart`, persisted via `LibraryTrackSortStore`.

| Mode | Order |
|------|--------|
| `folderOrder` (**default**) | Settings music-folder order, then relative path under each root |
| `modifiedNewest` / `modifiedOldest` | Catalog scan order / reverse |
| `titleAZ` / `titleZA` | Title, then path |

Shared by **Library → Songs** and **drawer → Files** (MP3 listings).

---

## Context track groups (Album now, Artist-ready)

Track overflow actions can open a dedicated grouped-track screen from the selected row.

- `TrackOverflowAction.albumTracks` launches `ContextTracksScreen`.
- Group matching is centralized in `lib/services/track_grouping.dart`:
  - `TrackGroupKind` (`album`, reserved `artist` for follow-up)
  - `TrackGroupRequest`
  - `resolveTracksForGroup(...)`
- Current implementation filters from `PlayerController.libraryCatalog` and plays only
  the grouped list (`setPlaylistAndPlay`) from:
  - `Play all` (index 0)
  - tapped track index in grouped list.

This keeps grouping logic reusable and UI-agnostic so adding Artist tracks later is a
new menu action + request type, not a second screen architecture.

---

## Recent behavior fixes (stability + UX)

- **Queue correctness:** "play from here" and folder/songs start points now keep the
  full list and set `startIndex` instead of truncating with `sublist(...)`.
- **Shuffle/scope safety:** "play from here" clears prior folder scope and disables
  inherited shuffle to prevent random carry-over after targeted starts.
- **Queue mutation stability:** reorder/play-next paths prefer in-place concat updates,
  defer expensive reloads while actively playing, and remap active order indexes to
  avoid UI/native desync.
- **Repeat-one correctness:** native loop mode is used and mutation-time completion
  noise is guarded to prevent brief incorrect auto-advance.
- **Startup empty state:** Songs/Recently Added show loading when folders exist but scan
  metadata is still initializing; "No tracks yet" is now reserved for true empty setup.
- **Drawer/menu UX:** Files route has its own drawer so hamburger remains in Files;
  shell drawer styling and text now follow active theme contrast.
- **Track info action:** overflow `Info` includes filename, size, duration, bitrate,
  and folder path via platform-safe metadata lookup services.

---

## Android home-screen widgets

Two providers: `Mp3PlayerAppWidget`, `Mp3PlayerGlassCardWidget`.

**Flutter → native:** `MethodChannel` `com.example.mp3_player/widget`

- `sync` — full state (track, art path, playing, position, theme).
- `syncPlaybackProgress` — position/playing only while app is foreground + playing.
- `setPlaying` — play/pause icon only.

**Prefs:** `mp3_player_home_widget` (`Mp3PlayerWidgetPrefs`).

**When app UI closes:** `Mp3PlayerAudioServiceActivity.onDestroy` / `onStop(finishing)`  
and Flutter `AppLifecycleState.detached` set **`playing: false`** so widgets show  
**play** (track info unchanged). Resumed lifecycle runs a full sync again.

**Transport buttons:** `WidgetMediaActionReceiver` → MediaSession (same as notification).

Widget placeholder art is drawn in Kotlin (`WidgetArtPlaceholderBitmap`); notification  
may still rasterize placeholders in Dart.

---

## Git & agent conventions

- **No Cursor co-author** in commit messages (see `.cursor/git-no-cursor-coauthor.mdc`).
- Optional hook: `git config core.hooksPath githooks` strips co-author trailers.
- **SMFACN** — *Stage Min Files and Commit New*: stage only files for the change,  
  one new commit, no co-author line.

---

## Related files (quick index)

| Topic | File |
|-------|------|
| Playback coordinator | `lib/audio/player_controller.dart` |
| Notifiers | `lib/audio/player_notifiers.dart` |
| Catalog | `lib/audio/library_catalog.dart` |
| Album art resolver | `lib/audio/album_art_resolver.dart` |
| Path disk cache | `lib/services/album_art_cache_io.dart` |
| Art availability | `lib/audio/art_availability_notifier.dart` |
| Sort | `lib/services/library_track_sort.dart` |
| Widget bridge | `lib/platform/android_home_widget_bridge.dart` |
| Widget sync | `lib/app.dart` (`_pushAndroidHomeWidgetState`) |
| Native widget | `android/.../Mp3PlayerWidgetSync.kt` |
