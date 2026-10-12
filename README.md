# Reson

A small native macOS local music player. v0.1 is a playback foundation: one Rust engine crate, a thin C ABI, and SwiftUI/AppKit. No accounts, telemetry, browser engine or runtime network access.

## Build and launch

Requires an Apple Silicon Mac, Xcode or Command Line Tools with Swift 5.9+, and Rust 1.87+ with the `aarch64-apple-darwin` target. Prefer an official Rust toolchain with a standard library compatible with the intended deployment OS.

```sh
./scripts/build.sh
./scripts/run.sh
```

The app is `build/Reson.app`. The first build downloads Rust dependencies; once cached, use `CARGO_NET_OFFLINE=true ./scripts/build.sh` for an offline build. Swift has no external package dependencies. Build again after source changes; run.sh launches an existing app without rebuilding it. Local ad-hoc signing is automatic; this is not a notarized distribution build.

The project targets macOS 14+, but this host's Homebrew Rust standard library was built for macOS 27. The linker warns about that mismatch. The generated app runs on this host; compatibility of this artifact with macOS 14–26 is **unverified**. Do not suppress the warning or ship this artifact to older systems without rebuilding with a compatible Rust standard library and testing there.

## Using v0.1

- Open one FLAC or WAV through Open File / Command-O. Opening starts playback.
- Files opened in this session appear in a native track table. Double-click a row to play it.
- Play/pause or Space pauses/resumes. Stop closes output and resets position; Play then restarts from the beginning.
- Toggle sidebar with Control-Command-S and inspector with Option-Command-I. The inspector follows selection; transport follows current playback.
- Metadata includes title/artist/album, source format, bit depth, rate, channels and duration where present. Missing values remain unavailable. Artwork is a native placeholder.
- Errors appear in the window. Open a valid file or retry Play after an output failure; a worker panic requires restarting the app.

Folder import, persistent library/SQLite, search/sorting, playlists, artwork caching, seeking, volume controls, grid view, queue UI, gapless transitions and output-device selection are planned, not implemented. Session tracks disappear when the app quits. Artists/Albums/Genres/Playlists are visibly unavailable.

## Checks

```sh
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/build.sh
(cd macos && swift test)
clang -fsyntax-only -x c macos/Bridge/include/reson.h
plutil -lint build/Reson.app/Contents/Info.plist
```

The test suite covers states, generation fences, in-flight replacement, queue saturation, teardown responsiveness, worker errors/panic, source metadata/decoded samples and C ownership/buffer rules. Swift tests cover acknowledgement refresh and rejection of old generations. Rust tests do not require an output device.

For explicit live-device testing, create two longer synthetic test files (ffmpeg is development-only):

```sh
mkdir -p build
ffmpeg -v error -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=30' -ac 2 -c:a pcm_s24le build/check.wav
ffmpeg -v error -y -i build/check.wav -c:a flac build/check.flac
cargo run --release -p reson-engine --example live_check -- build/check.wav build/check.flac
```

This starts audio on the current default output. It checks engine acknowledgements, pause/resume, stop/restart, EOF, missing-file recovery and shutdown. It does **not** independently capture or establish audible output.

See [validation](docs/validation.md), [audio behaviour](docs/audio-path.md), [benchmark protocol](docs/benchmarks.md) and [fixture provenance](tests/fixtures/README.md).

## Engine and bridge

`crates/engine` owns decoding/output on one worker; a bounded 16-command queue uses nonblocking enqueue. New accepted loads advance a generation fence; superseded queued loads are skipped and obsolete completions never replace current metadata. Stream setup and file operations run on the worker. Rust's backend is private to playback.rs, so the C interface and Swift do not depend on rodio types.

`macos/App/EngineBridge.swift` serializes all C calls on a dispatch queue. Rust owns the opaque handle; Swift destroys it once, off the main UI thread, after prior calls. UTF-8 paths are copied before the call returns. C snapshots contain fixed-layout scalars and JSON copied into caller-owned buffers, including a required-capacity result for resizing. Expected errors use statuses/snapshot messages; panics are contained at Rust entry points and the worker boundary. Invalid/dangling pointers, calls after destruction and overlapping destruction are outside the API contract. The header documents these rules.

UI refresh is 4 Hz while loading/playing or waiting for command acknowledgement, and stops in acknowledged stable states. The idle worker blocks on commands. Pause retains the output stream and may continue rendering silence. Rodio decodes through its callback iterator; strict real-time callback guarantees and bit-perfect output are **not** claimed. Shutdown waits for an in-flight file/device operation on a background queue; there is no forced thread cancellation or bounded shutdown guarantee for a stalled filesystem/driver.

## Licenses

MIT is proposed for original Reson code; the project license has not yet been selected, and there is no publication in this milestone. Dependencies retain their own licenses: rodio/cpal are MIT or Apache-2.0, Symphonia is MPL-2.0, serde_json is MIT or Apache-2.0. Check the complete locked dependency licenses before distribution. All fixtures are original synthetic PCM; no third-party music, application code or artwork is included.
