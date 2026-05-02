# Flutter MP3 Player (Android)

A Flutter Android app that lets the user pick a folder on the device, lists `.mp3` files inside it (recursively or only that folder—your choice when implementing), and plays them with a UI inspired by the reference design: deep navy header, white “card” body on **Now Playing**, track list on a navy screen, and a bottom **mini player**.

## Goals

1. **User-chosen path** — The user selects a directory (or you accept a typed/pasted path where the platform allows). The app scans that location for MP3 files.
2. **Local playback** — Play files from device storage using a Flutter audio plugin (no streaming requirement for v1).
3. **Polished UI** — Match the look and feel of the provided mock: colors (~`#1A233B` navy, white, grey text), heavy corner radius (~24–40), shadows on album art, slider progress, primary controls, optional stats row / list row layout as in the design.

## Reference design (summary)

| Area | Notes |
|------|--------|
| **Now playing** | Navy top bar: “Playing from” + source subtitle, menu + collapse chevron. White rounded panel: large art, title + artist, seek bar with times, prev / play-pause / next, optional bottom icon row. |
| **Track list** | Full navy screen: back, list title, rows with thumb, small meta (e.g. duration or path snippet), title + subtitle, overflow menu. |
| **Mini player** | White bar with thumb, title, compact prev / play / next, thin progress line. |

Implement layout and navigation first with placeholder data; wire real audio and folder scanning in following steps.

## Tech stack (recommended)

| Piece | Suggestion |
|-------|------------|
| **Flutter** | Stable channel, Android as first target. |
| **Audio playback** | [`just_audio`](https://pub.dev/packages/just_audio) — reliable for local files; add [`audio_service`](https://pub.dev/packages/audio_service) later if you want background playback and media controls. |
| **Folder / file picking** | [`file_picker`](https://pub.dev/packages/file_picker) (directory pick on supported Android versions) or [`saf_stream`](https://pub.dev/packages/saf_stream) / platform channels if you need SAF URIs; alternately [`permission_handler`](https://pub.dev/packages/permission_handler) + [`path_provider`](https://pub.dev/packages/path_provider) + manual path entry for debugging. |
| **Local metadata (optional)** | [`metadata_god`](https://pub.dev/packages/metadata_god) or similar for title/artist/album art from file tags. |
| **State** | `ChangeNotifier`, `Riverpod`, or `Bloc` — pick one and keep playlist + current index + position in one place. |

## Android storage and permissions

Modern Android restricts broad filesystem access. Plan for:

- **Android 13+ (API 33+):** Often `READ_MEDIA_AUDIO` (and/or photo/video if you expand). For **only** audio you pick via system picker, you may work with **content URIs** and won’t need “all files” access.
- **Older Android:** `READ_EXTERNAL_STORAGE` (and possibly `WRITE` only if you cache).
- **Scoped storage:** Prefer the Storage Access Framework (folder picker) or media-store APIs so users grant access to a specific tree; then enumerate/list `.mp3` under that tree per your implementation strategy.

Document in `android/app/src/main/AndroidManifest.xml` the exact permissions you use after you choose the pick-vs-path strategy.

## Functional requirements (v1)

- [ ] User selects or specifies a root folder for music.
- [ ] App discovers `.mp3` files (define: immediate children only vs recursive).
- [ ] Show list with title from filename or embedded metadata.
- [ ] Tap track to play; show Now Playing with seek bar and prev/next within the same list order.
- [ ] Mini player visible when user navigates away from full-screen player (if you use that navigation pattern).
- [ ] Handle basic errors: empty folder, permission denied, unreadable file.

## UI implementation notes (Flutter)

- **Colors:** Primary background `#1A233B` (navy), surfaces `#FFFFFF`, secondary text grey (`#8E99A8`–`#B0B8C4` range—tune for contrast).
- **Shapes:** `BorderRadius.circular(28)`–`40` for main sheets and art; `BoxShadow` under album art.
- **Progress:** `Slider` or `SliderTheme` with a round thumb; format `Duration` as `m:ss`.
- **Navigation:** e.g. `Navigator` push for track list ↔ now playing, or a single scaffold with toggled views.

## Project layout (suggested)

```
lib/
  main.dart
  app.dart                 # MaterialApp, theme (navy seed, typography)
 features/
    player/                # now playing, mini player widgets
    library/               # folder pick, track list
    audio/                 # wrapper around just_audio, playlist
```

Assets: optional default album placeholder; user’s art from metadata later.

## Step-by-step roadmap

Work through these in order; stop after any step to review.

1. **Bootstrap** — `flutter create .`, set `compileSdk` / `minSdk` in `android/app/build.gradle` (e.g. `minSdkVersion 23` or higher as needed by plugins).
2. **Theme + shell** — Navy scaffold, white rounded body widget matching the mock (static text and a placeholder `Container` for art).
3. **Dependencies** — Add `just_audio`, `file_picker`, `permission_handler`; run `flutter pub get`.
4. **Permissions** — Manifest + runtime requests; test on an emulator and a physical device.
5. **Folder pick + scan** — On success, build a `List<Track>` (path or URI, display name, duration if available).
6. **Playback service** — Single `AudioPlayer`, `setFilePath` or `setAudioSource` from URI; playlist: queue `ConcatenatingAudioSource` or manual track index.
7. **Wire UI** — List → play; Now Playing controls; mini player sync with `Stream` from player position/player state.
8. **Polish** — Metadata/art, loading and empty states, back stack behavior.

## How we’ll proceed together

Next steps from here can be:

- **A.** Scaffold the Flutter project and duplicate the theme/layout skeleton from your screenshot.  
- **B.** Lock the folder-selection strategy (directory picker vs URI-only vs debug path field).  
- **C.** Integrate `just_audio` with a hard-coded test `.mp3` path, then generalize to scanned files.

Tell me which letter you want first (or a different order), and we’ll implement it step by step in this repo.

## License

Specify your license when you publish (e.g. MIT); omit until you decide.
