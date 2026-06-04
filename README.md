# MadPlayer

A Flutter Android app that scans user-chosen music folders, plays local `.mp3` files with background audio and home-screen widgets, and uses a navy / glass UI (Now Playing, library, mini player).

**Architecture (playback, metadata, widgets, UI notifiers):** see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Goals

1. **User-chosen path** — Select music folders in Settings; app scans recursively for `.mp3` files.
2. **Local playback** — `just_audio` + `audio_service` / `just_audio_background` for background play and notifications.
3. **Polished UI** — Multiple themes (Julia, Leah, Silver, Daisy, Ivy, …), liquid glass / mini player, library tabs.
4. **Context actions** — Track overflow supports `Album Tracks` and `Info` (file details + technical metadata).

## Tech stack

| Piece | Usage |
|-------|--------|
| **Flutter** | Android primary; Windows/desktop supported with playback caveats. |
| **Audio** | [`just_audio`](https://pub.dev/packages/just_audio), [`just_audio_background`](https://pub.dev/packages/just_audio_background) (local fork under `packages/`) |
| **Folders** | [`file_picker`](https://pub.dev/packages/file_picker), [`permission_handler`](https://pub.dev/packages/permission_handler) |
| **Metadata** | [`audio_metadata_reader`](https://pub.dev/packages/audio_metadata_reader); optional [`metadata_god`](https://pub.dev/packages/metadata_god) (Rust) with Dart fallback. **Tag edits:** ID3v2 (MP3), Vorbis/FLAC/MP4 via the reader; **APEv2** via `lib/services/ape_tag_writer_io.dart` (see architecture doc). |
| **Persistence** | SharedPreferences (`*Store`), Isar (`SongMetadataCache`) |
| **State** | `PlayerController` + split notifiers (`positionNotifier`, `track`, `playback`, `queue`) — see architecture doc |

### `metadata_god` on Windows

Pins `flutter_rust_bridge: 2.11.1` in `pubspec.yaml` to match `metadata_god` 1.1.0.

**`Get-Item : Could not find item ...\AppData` (resolve_symlinks.ps1)**

Cargokit resolves paths segment-by-segment; `Get-Item` without `-Force` fails on the hidden `AppData` folder under your user profile. After `flutter pub get`, run:

```powershell
powershell -ExecutionPolicy Bypass -File tool\patch_cargokit_resolve_symlinks.ps1
```

Then `flutter run -d windows` again. Re-run the patch after `flutter pub get` or `flutter clean` if the error returns.

**os error 4551 — Application Control policy blocked**

If Cargokit logs **“An Application Control policy has blocked this file”** while compiling crates under `build\metadata_god\`, Windows is blocking Rust **build scripts**.

**Fix (pick one):**

1. **Allow dev builds:** Smart App Control off, or Controlled folder access allowlist for `rustc`/`cargo` and the project folder (corporate WDAC may need IT).
2. **Skip Rust:** Remove `metadata_god` from `pubspec.yaml`. `--dart-define=USE_METADATA_GOD=false` only disables runtime use; the native plugin still builds while the dependency remains.

After policy changes: `flutter clean`, delete `build\metadata_god`, then `flutter run`.

## Android storage and permissions

- **Android 13+:** `READ_MEDIA_AUDIO` (and related) via `permission_handler` / storage helpers.
- Prefer SAF folder picks where applicable; library paths stored in Settings.

See `android/app/src/main/AndroidManifest.xml` for declared permissions.

## Playback (summary)

On Android, the queue is a single **`ConcatenatingAudioSource`** with **lazy preparation**.  
**Skip next/previous** uses `seek(index:)` on the same source — not a full reload.

Full **`setAudioSource`** reload happens for a new playlist, shuffle toggle (next transport), path changes, or when in-place **`add` / `insert` / `removeAt`** cannot be used. Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Library sort

Default: **folder order** (Settings folder list, then path under each root).  
Other modes: date modified, title A–Z / Z–A. Shared by Songs tab and Files browser (`LibraryTrackSortStore`).

## Track overflow highlights

- **Album Tracks:** Opens a dedicated grouped screen and plays only tracks in the same album.
- **Info:** Shows filename, file size, duration, bitrate, and folder path.
- Grouping internals are reusable (`lib/services/track_grouping.dart`) so Artist-based grouping can be added without rebuilding screen architecture.

## Project layout

```
lib/
  main.dart, app.dart
  audio/                 player_controller, notifiers, library_catalog
  features/
    library/             songs, files, queue
    player/              now playing, mini player
    shell/               scan, sync, drawer
  services/              metadata, cache, sort, stores
  platform/              android_home_widget_bridge
docs/
  ARCHITECTURE.md        detailed design notes
```

## License

Specify your license when you publish (e.g. MIT).
