# finder

A desktop download manager for videos and playlists **you own or are authorized
to access**. Built with Flutter from a single Dart codebase for **macOS (Apple
Silicon and Intel)** and **Windows x64**. It drives
[yt-dlp](https://github.com/yt-dlp/yt-dlp) for extraction and downloading, and
[FFmpeg](https://ffmpeg.org) for merging and audio extraction. Everything runs
locally: there is no backend, telemetry or upload of any kind.

> finder does not bypass DRM, paywalls, sign-in requirements or other access
> restrictions. Respect copyright and the terms of the platforms you use.

---

## Features

| Area | What you get |
| --- | --- |
| **Dashboard** | URL input with validation, paste-from-clipboard, and Detect. Shows thumbnail, title, channel, video count, total duration, and a selectable list of playlist entries (lazily built, so large playlists stay fast). |
| **Metadata** | `yt-dlp --dump-single-json --flat-playlist`, parsed off the UI isolate. Handles single videos, playlists, and partially unavailable playlists (private, deleted, members-only, live, nested playlists are flagged and can't be selected). |
| **Quality** | Best, 2160p, 1440p, 1080p, 720p, 480p, 360p. For a single video, **only resolutions that actually exist** can be picked. For playlists, each video gets the best stream at or below your choice, and you're told when a video didn't have it (the resolution is checked against the finished file). |
| **Formats** | MP4, MKV, or original container. Streams are merged/remuxed **without re-encoding**. Audio-only: best original audio (no re-encode) or MP3 (re-encoded, 320/192/128 kbps or VBR V0). |
| **Download manager** | Queue with configurable concurrency (1–6), per-item progress, speed, size, ETA, stream index, queue position, reorder, pause/resume, cancel (removes partial files), retry, skip already-completed items, duplicate prevention. All numbers come from yt-dlp's real output; nothing is estimated by finder. |
| **History** | SQLite-backed. Search, filter by status and date (today / 7 / 30 days / custom range), open file, show in folder, retry, remove records, detection of moved/deleted files. Downloads interrupted by quitting are marked *Interrupted* on next launch. |
| **Settings** | Default folder, resolution, container, audio format/quality, concurrency, playlist numbering, skip completed, custom executable paths, theme (dark/light/system), logging level, notifications, system certificates. |
| **Dependencies** | Detects yt-dlp and FFmpeg (custom path → app-managed → bundled → PATH → well-known locations), validates them, shows versions, and installs or updates verified official builds in one click. |
| **Reliability** | Typed errors with plain-language messages, rotating and sanitized local logs, safe child-process cleanup on quit. |

## Architecture

```
lib/
  main.dart                  bootstrap: paths → logging → SQLite → settings → ProviderScope
  app.dart                   MaterialApp.router, theme, graceful shutdown (AppLifecycleListener)
  core/
    config/                  AppConfig, official dependency sources, AppPaths
    di/providers.dart        Riverpod service graph (all overridable in tests)
    errors/                  AppError (typed, user-safe) + ErrorClassifier (yt-dlp stderr → kind)
    logging/                 rotating file logger + sanitizer (home path, URL credentials)
    routing/                 GoRouter with a ShellRoute (sidebar + content)
    theme/                   design tokens (AppPalette), Material 3 theme
    utils/                   URL validation, formatting, path safety, platform detection
  models/                    typed, immutable models (MediaInfo, DownloadOptions, DownloadTask, …)
  services/
    process_service.dart     Process.start wrapper: no shell, live-process registry, tree kill
    metadata_service.dart    metadata extraction (JSON parsed in an isolate)
    downloader_service.dart  yt-dlp download jobs → typed event stream + outcome
    ffmpeg_service.dart      version detection, ffprobe resolution probing
    dependency_manager.dart  locate / validate / install / update yt-dlp + FFmpeg
    binary_installer.dart    HTTPS download + SHA-256 verification + retries
    trust_store_service.dart OS certificate trust for yt-dlp (corporate TLS inspection)
    storage_service.dart     SQLite (FFI, background isolate) + migrations
    ytdlp/                   pure argument builder, output parser, metadata parser
  features/
    dashboard/  downloads/  queue/  history/  settings/  about/  shell/
      application/           Riverpod controllers
      data/                  repositories (SQLite)
      domain/                DownloadManager (pure Dart scheduling engine)
      presentation/          screens + widgets
  widgets/                   shared design-system components
```

UI, business logic, persistence and process execution are separated by
interfaces (`MetadataService`, `DownloaderService`, `HistoryRepository`,
`SettingsRepository`, `NotificationService`, `FileOpenerService`,
`DirectoryPicker`). The `DownloadManager` is plain Dart with no Flutter
dependency, so it's fully unit-tested with fakes.

**Packages:** flutter_riverpod 3, go_router 18, sqflite_common_ffi (prebuilt,
hash-pinned SQLite via `sqlite3` build hooks), path_provider, file_selector,
logging, crypto, intl, flutter_local_notifications.

### How a download runs

1. yt-dlp is started with `Process.start(exe, [args…], runInShell: false)`. The
   URL is validated (http/https only), passed as a separate argument, and placed
   after `--`, so it can never be read as an option or shell syntax.
2. `--ignore-config` stops a user's global yt-dlp config from changing behaviour.
3. Progress comes from a machine-readable `--progress-template`
   (`[cg]dl|status|downloaded|total|estimate|speed|eta|fragment|count|format`),
   plus post-processing events and `--print after_move:filepath`.
4. Format selection: `-f "bv*+ba/b"` with `-S res:<N>` picks the best stream at
   or below N (short-side resolution, so vertical video works), with
   `--merge-output-format`/`--remux-video` for MP4/MKV. Nothing is re-encoded
   except for MP3.
5. **Pause** stops the process but keeps `.part` files; **resume** restarts
   yt-dlp, which continues from the partial data. (yt-dlp has no in-process
   pause.) **Cancel** stops it and removes only temporary files that match that
   item.
6. Stopping is graceful first (SIGINT, so yt-dlp shuts down FFmpeg), then the
   whole process tree is force-killed after a grace period (`taskkill /T /F` on
   Windows). On quit, every child process is stopped before the app exits.

## Requirements

| | |
| --- | --- |
| macOS | 10.15+ on Apple Silicon (arm64) or Intel (x64) |
| Windows | Windows 10 1803+ / Windows 11, x64 (arm64 runs the x64 build) |
| Build tools | Flutter 3.47+ (Dart 3.13+). macOS builds need **full Xcode**. Windows builds need **Visual Studio 2022 with "Desktop development with C++"**. |

## Building

```bash
flutter pub get
flutter analyze
flutter test

# macOS (on a Mac with Xcode)
flutter build macos --release        # → build/macos/Build/Products/Release/finder.app
tool/package_macos.sh                # same, plus bundled deps + inside-out codesign

# Windows (on Windows with Visual Studio 2022)
flutter build windows --release      # → build\windows\x64\runner\Release\
```

Windows builds must be produced and tested on Windows, and macOS builds on macOS.

### Bundling dependencies (optional)

End users can install yt-dlp from **Settings → Dependencies** with one click, so
bundling is optional. To ship a self-contained package instead:

```bash
# Windows: verified yt-dlp (onedir) + FFmpeg (yt-dlp/FFmpeg-Builds, GPL)
dart run tool/fetch_dependencies.dart --platform windows   # → third_party/windows/bin
flutter build windows --release                            # CMake copies it to <install>\bin

# macOS: verified yt-dlp; bring an FFmpeg build you trust
dart run tool/fetch_dependencies.dart --platform macos --ffmpeg /path/to/ffmpeg
tool/package_macos.sh                                       # → finder.app/Contents/Resources/bin
```

At runtime finder looks in `finder.app/Contents/Resources/bin` (macOS)
and `<install dir>\bin` (Windows).

## Dependency configuration

| Tool | Auto-install | Source | Verification |
| --- | --- | --- | --- |
| yt-dlp | macOS + Windows | Official GitHub release, *onedir* build (`yt-dlp_macos.zip`, `yt-dlp_win.zip`) | SHA-256 against the release's `SHA2-256SUMS` |
| FFmpeg | Windows | `yt-dlp/FFmpeg-Builds` (`ffmpeg-master-latest-win64-gpl.zip`) | SHA-256 against `checksums.sha256` |
| FFmpeg | macOS: manual | FFmpeg publishes source only. Use a build linked from ffmpeg.org, or an existing install (`/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin` are detected automatically; Homebrew is **not** required). | Validated by running `-version` |

- Binaries are only made executable after their checksum matches. An asset
  without a published checksum is refused.
- Note that the checksum list comes from the same GitHub release as the binary.
  This protects integrity in transit, but it doesn't independently prove the
  publisher's identity. yt-dlp also publishes GPG signatures (`SHA2-256SUMS.sig`)
  for manual verification.
- The **onedir** yt-dlp builds are used because the single-file builds unpack
  themselves on every launch, which the OS re-scans each time (about 30 s per
  call on macOS). The onedir build's first launch takes about 30 s once; after
  that it starts in about 0.4 s.
- Custom paths (**Choose file…**) are validated before use: absolute path,
  expected file name (`yt-dlp*`, `ffmpeg*`), executable bit or `.exe`, and a
  successful version probe. A configured custom path is never silently
  replaced.
- **Update**: yt-dlp installed by finder can be updated in place. Copies
  installed some other way should be updated by whatever installed them.
- Managed binaries live in the app data folder: `~/Library/Application
  Support/com.finder.finder/bin` on macOS and
  `%APPDATA%\finder\finder\bin` on Windows.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| *yt-dlp is not set up* | Settings → Dependencies → **Install**. |
| *FFmpeg is required…* | Windows: **Install**. macOS: **Choose file…** and select an `ffmpeg` binary (keep `ffprobe` beside it). |
| *Secure connection failed* / `CERTIFICATE_VERIFY_FAILED` | Your network inspects HTTPS (common on managed work computers). Keep **Settings → Network → Use system certificates** enabled: yt-dlp then trusts the OS store (macOS Keychain roots exported to a PEM file; the Windows certificate store). Verification is never turned off. |
| First check after installing yt-dlp is slow | Expected once (about 30 s) while the OS scans the new binary. |
| *Format unavailable* | The video doesn't offer that format. Choose *Best available* or another container. For YouTube, newer yt-dlp versions may need an external JavaScript runtime to list all formats. See the yt-dlp docs. |
| *Access restricted* | The content is private, members-only or needs sign-in. finder won't bypass that. |
| *Permission denied* | Choose a destination folder you can write to. |
| Anything else | Settings → Diagnostics → **Open logs folder**. Logs redact your home path and credential-like URL parameters. |

## Known limitations

- **macOS builds were not produced in this environment**: full Xcode wasn't
  installed, and `flutter build macos` requires it. Analysis, the full test suite,
  and real yt-dlp end-to-end runs were done on macOS arm64.
- **Windows builds weren't produced or tested here** (they need Windows + Visual
  Studio). The Windows code paths (`taskkill /T`, `explorer /select,`, `.exe`
  validation, `bin` bundling, WM_GETMINMAXINFO) follow platform APIs, and the
  Windows dependency archives were downloaded, verified and checked for the
  expected layout from macOS.
- Pause/resume is stop-and-continue (yt-dlp has no in-process pause). Resuming
  relies on the server supporting HTTP range requests; otherwise the item
  restarts from the beginning.
- Progress of merged downloads is reported per stream (video, then audio)
  because yt-dlp doesn't announce the second stream's size in advance.
- If the app is force-killed (not quit), running yt-dlp processes may survive.
  A normal quit (⌘Q / window close) always cleans them up.
- The app is distributed outside the Mac App Store with the App Sandbox disabled.
  Sandboxed child processes inherit the sandbox and couldn't write to
  user-chosen folders. Use Developer ID signing + notarization for distribution
  (`CODESIGN_IDENTITY=… tool/package_macos.sh`).
- Windows notifications use the Windows toast APIs and may need the app to be
  installed (MSIX or a registered AUMID) to appear.

## Development tools

| Command | Purpose |
| --- | --- |
| `flutter test` | Unit, widget, persistence, and mock-executable integration tests |
| `dart run tool/smoke_test.dart <dir> [url]` | Real end-to-end check: installs verified yt-dlp, extracts metadata, downloads with finder's exact arguments (`SMOKE_REAL_ARGS=1` to skip the no-FFmpeg fallback) |
| `flutter test tool/screenshots/render_screens_test.dart` | Renders every screen to `build/screenshots/*.png` with real fonts |
| `python3 tool/generate_icons.py` | Regenerates the macOS and Windows app icons |

## License notes

yt-dlp is released under the Unlicense. FFmpeg is LGPL/GPL depending on the
build (the Windows builds finder installs are GPL, and their license file is
saved next to the binaries). See **About → View all open-source licenses** for
the Dart/Flutter packages.
