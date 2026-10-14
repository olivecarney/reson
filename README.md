# Reson

A lightweight native macOS player for local lossless music.

Rust handles playback. SwiftUI and AppKit provide the interface. No accounts, telemetry, cloud services or browser engine.

**Status: v0.4 playback and audio refinements.** Seek and scrub local FLAC/WAV tracks, adjust app volume/mute, select output devices, and inspect source versus output formats. Persistent playlists, independent queues and M3U8 exchange remain available.

See [audio behaviour and controls](docs/audio-v0.4.md), [v0.4 validation and measurements](docs/validation-v0.4.md), and [playlist behaviour](docs/playlists-v0.3.md).

v0.2 adds a background Rust library worker using macOS system SQLite through `rusqlite`, without bundled SQLite. See the [library design](docs/library-v0.2.md), [validation and measurements](docs/validation-v0.2.md), and [database decision](docs/spikes/system-sqlite.md).

v0.2.1 adds lazy embedded FLAC/WAV artwork, native ImageIO thumbnails and a bounded memory cache backed by `~/Library/Caches/Reson/Artwork/`. See the [artwork architecture](docs/artwork-v0.2.1.md) and [validation results](docs/validation-v0.2.1.md). Selection and playback artwork stay independent. Manual rescan refreshes changed sources; artwork is never fetched online.

## What works

- FLAC and PCM WAV playback through a small Rust engine.
- Play, pause, resume, stop, next/previous and automatic end-of-track progression.
- Persistent playlists with native multiple-row drag/drop, duplicate entries and keyboard editing.
- In-session queue with Play Next, append, reorder, remove and clear.
- Local UTF-8 M3U8 import and atomic export.
- Persistent recursive folder imports, cancellation, duplicate prevention and manual rescans.
- Native track table with search, column sorting and missing-file indicators.
- Title, artist, album, genre, tagged BPM/key and audio properties where available.
- Dark interface, translucent sidebar and collapsible inspector.
- Native file picker, double-click playback and macOS shortcuts.
- Background file setup and shutdown, with protection against stale track metadata during rapid replacement.

Folder imports persist in `~/Library/Application Support/Reson/library.db`. Files opened individually remain session-only. Tracks without embedded artwork use a placeholder. The sidebar contains Library and persistent playlists.

## Build and run

### Requirements

- An Apple Silicon Mac.
- Xcode or Command Line Tools with Swift 5.9 or newer.
- Rust 1.87 or newer with the `aarch64-apple-darwin` target.

```sh
git clone https://github.com/olivecarney/reson.git
cd reson
./scripts/build.sh
./scripts/run.sh
```

The build produces **`build/Reson.app`**, which you can also open directly. The app is signed locally with an ad-hoc signature; it is not notarized for distribution.

The first build downloads Rust dependencies. Swift has no external package dependencies. After dependencies are cached, build offline with:

```sh
CARGO_NET_OFFLINE=true ./scripts/build.sh
```

Run `build.sh` after changing source files. `run.sh` launches the existing build and only builds when the app is missing.

### macOS compatibility

The project requests macOS 14 or later. The initial build machine's Homebrew Rust standard library targets macOS 27, producing linker warnings when linked for macOS 14. That artifact was tested on the build machine; compatibility with macOS 14–26 remains unverified. For older systems, use a Rust standard library compatible with the target OS and test the resulting app there.

## Controls

| Action | Control |
| --- | --- |
| Open and play a file | **⌘O** or Open File |
| Import a folder | **⇧⌘O** or Import Folder |
| Rescan saved folders | File → Rescan Folders |
| Search / sort | Search field / column headers |
| Play a track | Double-click its row |
| Pause / resume | **Space** or the playback button |
| Stop and reset position | Stop button |
| Seek / scrub | Click or drag the timeline; arrow keys ±5 seconds, Home/End |
| App gain / mute | Volume slider / speaker button; saved between launches |
| Output selection / recovery | Speaker device menu; Refresh Devices / Retry Selected Output |
| Source and output diagnostics | Transport info button |
| Create playlist | **⌘N** |
| Import / export M3U8 | **⇧⌘I** / **⇧⌘E** |
| Show queue | **⌘J** |
| Next / previous | **⌥⌘N** / **⌥⌘P** |
| Move selected playlist/queue rows | **⌥⌘↑** / **⌥⌘↓** |
| Remove selected playlist/queue rows | **Delete** |
| Toggle sidebar | **⌃⌘S** |
| Toggle inspector | **⌥⌘I** |

The inspector follows the selected row; the playback bar follows the currently playing file. After Stop, Play restarts from the beginning.

## Architecture

```text
SwiftUI / AppKit
  ├─ Audio bridge queue → Rust playback worker → rodio / cpal / CoreAudio
  └─ Library bridge queue → Rust library worker → LibraryStore / system SQLite
```

One Rust crate owns playback and the separate `LibraryStore`. A dedicated library worker owns system SQLite and scans one file between command checks. A second Swift bridge queue owns library calls and shutdown. The UI loads saved metadata without rescanning audio. Searches bind parameters; paged C responses use caller-owned buffers. WAL with synchronous FULL retains each completed import if indexing is cancelled or interrupted. Missing records remain in the library; moved/renamed files create a new path identity on rescan.

The Rust crate owns the playback backend. A bounded command queue keeps file and device setup off the main UI thread. Accepted loads advance a generation fence so superseded work cannot publish old metadata. Swift serializes bridge calls and destroys the engine on a background queue.

```text
crates/engine/     Playback, library store/scanner/worker, C exports and tests
macos/App/        App lifecycle, observable state and bridge ownership
macos/Views/      SwiftUI layout and AppKit track table
macos/Bridge/     C header and Swift module maps
scripts/          Build, launch and fixture generation
tests/fixtures/  Original synthetic WAV/FLAC test data
docs/            Audio behaviour, validation and benchmark protocol
```

The [C header](macos/Bridge/include/reson.h) documents pointer ownership, buffer sizing, status codes and threading. Rodio-specific types stay inside the playback implementation so the backend can be replaced without changing the Swift interface.

## Audio behaviour

Lossless input does **not** imply bit-perfect output. The player supports System Default and explicitly selected outputs and reports source properties separately from the configured output stream. Live checks observed 44.1 kHz sources feeding a 48 kHz stereo F32 stream, involving rate conversion.

Rodio can read files, decode, allocate and lock through its output callback path. Strict real-time guarantees are not met by this prototype. Pause retains the output stream; Stop and EOF release it. Shutdown waits for in-flight file/device operations on a background queue.

Live engine state checks passed for WAV and FLAC, including pause/resume, stop/restart, EOF, error recovery and shutdown. Audible output was not independently verified by listening or loopback capture.

See [audio-path notes](docs/audio-path.md) and the [validation record](docs/validation.md) for evidence and remaining gaps.

## Development checks

```sh
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/build.sh
(cd macos && swift test)
clang -fsyntax-only -x c macos/Bridge/include/reson.h
plutil -lint build/Reson.app/Contents/Info.plist
```

The v0.2 validation results and reproducible benchmarks are recorded in [validation-v0.2.md](docs/validation-v0.2.md). Rust tests run without an audio output device.

Fixtures are checked in; regenerating them requires Python 3 and ffmpeg:

```sh
python3 scripts/generate-fixtures.py
```

See [fixture provenance](tests/fixtures/README.md). For explicit live-device checks, generate longer test files and run the smoke-check example:

```sh
mkdir -p build
ffmpeg -v error -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=30' -ac 2 -c:a pcm_s24le build/check.wav
ffmpeg -v error -y -i build/check.wav -c:a flac build/check.flac
cargo run --release -p reson-engine --example live_check -- build/check.wav build/check.flac
```

This plays a synthetic tone on the default output device. It verifies engine behaviour, not physical output precision.

For the v0.4 opt-in silent native checks and muted transition benchmark:

```sh
python3 scripts/generate-v0.4-fixtures.py build/v0.4-audio
RESON_AUDIO_FIXTURES="$PWD/build/v0.4-audio" RESON_NATIVE_PLAYBACK_TEST=1 swift test --package-path macos --filter 'AudioRefinementIntegrationTests|TransitionIntegrationTests|PlaylistIntegrationTests'
cargo run --release -p reson-engine --example audio_bench -- build/v0.4-audio
```

System Default is selected at each launch. Explicit devices do not silently fall back when unavailable. Gain/mute persist through local preferences; no global output or volume settings are changed. True gapless playback remains deferred with measured timing evidence.

## Next milestones

1. Broader native UX refinement (v0.5).
2. Further library organisation.
3. True gapless playback after an architecture and captured-continuity investigation.

Library benchmarks cover 270, 5,000 and 25,000 synthetic metadata records. Full Unicode case folding, automatic file watching and moved-file relinking are deferred. Older macOS compatibility and audible output remain unverified.

## License

A license for original Reson code has not yet been selected; MIT is proposed. Until a license is added, this repository should not be treated as MIT-licensed.

Dependencies retain their own licenses, including rodio/cpal (MIT or Apache-2.0), Symphonia (MPL-2.0) serde/serde_json (MIT or Apache-2.0), rusqlite (MIT), and system SQLite (public domain). Fixtures are original synthetic audio; no third-party music, artwork or application code is included.
