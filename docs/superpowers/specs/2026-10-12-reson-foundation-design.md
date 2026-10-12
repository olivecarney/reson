# Reson: native lossless playback foundation

Status: proposed written specification. The architecture and milestone scope were approved in conversation; this document awaits review before implementation planning.

## Purpose and milestone

Build a lightweight, local-first macOS music player for an Apple Silicon MacBook Air. The first milestone is a polished native window that opens a local FLAC or PCM WAV file and supports play, pause, resume and stop through a small Rust engine. Playback and file opening must not block the main UI thread.

The complete product brief remains the longer-term direction. This milestone does not implement folder indexing, persistent playlists, M3U export, gapless transitions, output-device selection or an audio-path certification. The interface must distinguish implemented actions from later features.

The visual reference mentioned in the brief is unavailable in this conversation. Use the written layout description: dark restrained surfaces, native typography, a narrow translucent sidebar, a track table, optional inspector and compact transport bar. No generated artwork or invented library records.

## Architectural choice

Use one Rust engine crate, built as a static library, and a Swift Package executable using SwiftUI and AppKit. A build script links the Rust library and packages the executable into a runnable macOS `.app` with an Info.plist. Target arm64 macOS 14 or later initially; an Xcode project, universal binaries, signing and distribution are later work.

Choose rodio with Symphonia FLAC/WAV decoding for this prototype. Disable unnecessary codec features where the selected release permits it. Resolve the release and inspect its actual API during implementation, then commit Cargo.lock. Rodio delegates output to cpal, whose macOS backend uses CoreAudio. All rodio-specific types remain inside playback.rs so Swift and the C interface do not depend on its API.

Alternatives considered: Symphonia plus cpal directly provides more explicit sample and callback control but requires decoding, buffering and conversion infrastructure; direct CoreAudio provides the most platform control but adds a larger unsafe integration surface. Revisit these choices when output verification or callback inspection shows a concrete limitation.

Proposed layout:

```text
Cargo.toml
Cargo.lock
crates/engine/Cargo.toml
crates/engine/src/{lib,playback,ffi}.rs
macos/Package.swift
macos/App/
macos/Views/
macos/Bridge/                # C header and Clang module
scripts/{build,run}.sh
tests/fixtures/
docs/superpowers/specs/
README.md
```

Do not introduce empty library or core crates. Separate indexing and persistence when those responsibilities actually exist. SQLite is deferred: there is no persistent library in this milestone, so neither a database nor a competing persistence format is necessary yet.

## Playback and threading

The signal path is local file → Symphonia via rodio → rodio output layer → cpal → CoreAudio → default device.

A single Rust worker owns the decoder, playback object and output stream. It waits for commands when inactive rather than busy polling. Swift enqueues commands through the bridge; opening, probing and audio setup occur on the worker. Dependency-managed output threads are additional to this worker and must be documented from the selected version rather than assumed absent.

Commands are load-and-play, play/resume, pause, stop and shutdown. The command queue is bounded; enqueueing never waits for decoder completion, and a full or disconnected queue returns a visible error. Loading a new file replaces the current source. Track replacement, stop and shutdown dispose of superseded playback resources. Idle startup does not create an audio stream. Stop releases the active source and stream while retaining the selected path and metadata; play after stop reloads from the beginning. Pause retains playback position. Shutdown joins the worker outside the main UI thread.

States are empty, loading, playing, paused, stopped, ended and error. Opening a file enters loading; successful setup enters playing. End of file enters ended. Play from ended or stopped starts at the beginning. Pause and resume preserve position. Stop resets position to zero. An invalid file or unavailable output enters error, and a subsequent valid load can recover. Rapid replacement must not publish stale metadata as the current track.

Expose copied snapshots containing state, current position, duration when known, source format, sample rate, channel count and bit depth when known, plus error details. Unknown metadata is displayed as unavailable, not guessed. Read headers/container information without decoding an entire file to get metadata. Embedded artwork can be omitted for this phase; use a quiet native placeholder.

Swift refreshes snapshots at a modest rate while playing or loading and while a command acknowledgement is pending. Stop periodic refreshes once a stable idle or paused state is acknowledged. Completion detection is bounded by the active refresh interval. No continuously animated idle views.

## Rust–Swift boundary

Use a handwritten C ABI and Clang module imported by Swift. Rust exports an opaque engine handle, lifecycle functions, command functions and a snapshot function. The Swift wrapper is the sole owner of the handle and serializes its use. Destruction happens once, after in-flight bridge calls finish; calling with a destroyed handle is invalid.

Paths cross as UTF-8 bytes with explicit lengths. Rust copies the bytes before returning, so the caller's buffer is borrowed only for the call. Reject null pointers with nonzero lengths and invalid UTF-8 as explicit errors. Paths are never concatenated into shell commands.

Snapshots use fixed-layout C scalars and caller-owned buffers for variable-length text, with required lengths reported if buffers are too small. No Swift-managed object crosses into Rust, and Rust-owned string memory never needs to be freed by Swift. Document enum discriminants, buffer capacities, null handling and ownership in the header.

Expected errors return status codes and explanatory messages; they do not panic. Contain unwinding panics at exported functions and at the worker boundary, mark failed engine state explicitly and prevent panics from crossing into Swift. This does not guarantee recovery from aborts or process-level allocation failure. Never invoke Swift callbacks from an audio callback.

## Native window

Use a SwiftUI scene with a default dark appearance and ordinary macOS resizing. Aim for an initial window around 1180 × 740 points and a usable minimum around 820 × 520 points.

- Sidebar: All Tracks is functional for the session's opened files. Artists, Albums, Genres and Playlists are visibly unavailable or labelled as planned, without dead clickable actions. Sidebar visibility can be toggled.
- Centre: an NSTableView hosted in SwiftUI renders opened files with small artwork placeholders and title, artist, album, BPM, key, format and duration columns. Missing tags use sensible filename fallback for title and an em dash for other absent fields. Select a row and double-click to play it. Folder import, multi-selection playlist operations, grid mode and advanced sorting/search are deferred.
- Inspector: a toggleable read-only panel shows the selected file's actual available metadata and path. It does not mislabel selection as the currently playing track.
- Transport: current file title, play/pause, stop and elapsed/duration display. Previous/next, shuffle/repeat, seek and volume controls are omitted or visibly disabled until implemented. Do not display a decorative seek slider that suggests seeking works.
- Native actions: Open File via NSOpenPanel and Command-O; Space toggles playback when focus is not in a text control; inspector/sidebar commands have menu entries. Error text is visible, actionable and recoverable. Controls reflect engine acknowledgement rather than assuming success.

UI implementation must use original styling. The app contains no browser engine, accounts, telemetry or network calls.

## Audio risks and actual claims

Lossless input does not establish bit-perfect output. Rodio may convert sample format, channels or rate, and macOS output can mix or convert audio. Record the source format separately from the configured output stream format, where accessible. Do not present configured stream rate as verified hardware rate or source bit depth as output precision.

Inspect the selected dependency implementation for decoder work, allocation and locks in the output callback path. Keep all application-level file I/O, metadata extraction, setup and command synchronization out of the callback. The prototype must document any dependency callback limitations; it must not claim the brief's strict real-time properties until verified. If inspection shows unacceptable blocking in the callback, propose replacing the backend with worker-decoded bounded PCM buffering before claiming that requirement complete.

Initial validation covers representative 16/24-bit PCM WAV and FLAC at 44.1 and 48 kHz. Unsupported variants fail explicitly. Higher rates and 32-bit PCM may work through the decoder but remain unverified until tested. Gapless playback, automatic hardware-rate changes, exclusive device access and precision guarantees are deferred.

Device absence, initialization failure and reported stream failure must yield visible errors. Automatic recovery after device replacement is deferred; opening or playing again should retry output setup.

## Validation and acceptance

1. Cargo tests verify playback state rules, end/restart behaviour, command ordering and recoverable errors without requiring an output device.
2. Decoder fixture tests read generated or redistributable FLAC/WAV samples, check properties and decoded samples, and reject malformed input. Fixture provenance and reproduction are documented.
3. FFI tests exercise lifecycle, copied path lifetime, buffer sizing and invalid input; ordinary caller misuse such as use-after-destroy remains outside the API contract.
4. Release Rust and Swift compilation succeeds on arm64 macOS, and build/run scripts create and launch the app without runtime network access. Initial dependency downloads require network access; document subsequent offline builds after caching.
5. Native UI verification checks opening files, table rendering, inspector/sidebar toggles, playback controls, error recovery and resizing. A decoder test is not evidence of audible output. A live device test and listening or loopback verification are reported separately, with any unverified step clearly stated.
6. Document a reproducible baseline protocol for cold startup, idle memory/CPU and playback CPU using a release build, fixed files, device/rate settings, measurement duration and repetitions. Do not invent numerical performance results or targets. Indexing benchmarks begin with Phase 2.

The milestone is complete only when the packaged native window runs and a real local FLAC and WAV can be played, paused, resumed and stopped through Rust, with build instructions and an honest record of validation and limitations. If audible playback cannot be independently confirmed, report that remaining acceptance gap.

## Documentation and licensing

README includes Apple Silicon prerequisites, build/run commands, implemented versus planned functionality, bridge ownership/threading rules and the actual audio-path limitations. Propose MIT for original project code, subject to the user's choice before publication; dependencies retain their own licenses, including Symphonia's MPL-2.0 requirements. No third-party application code or assets are copied.

Primary references consulted during design:

- https://docs.rs/rodio/latest/rodio/
- https://docs.rs/cpal/latest/cpal/
- https://doc.rust-lang.org/nomicon/ffi.html
- https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/WhatsinCoreAudio/WhatsinCoreAudio.html
