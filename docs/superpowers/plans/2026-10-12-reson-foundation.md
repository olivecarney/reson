# Reson Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a runnable Apple Silicon macOS window that opens and plays local FLAC/PCM WAV through Rust, with pause, resume and stop.

**Architecture:** A Rust static library owns playback on one command worker. A handwritten C ABI exposes commands and copied snapshots to a SwiftUI app with an AppKit table. Rodio and its output dependencies stay behind the Rust playback implementation.

**Tech Stack:** Rust, rodio with Symphonia FLAC/WAV, cpal/CoreAudio, SwiftUI, AppKit, Swift Package Manager, shell build scripts.

**Spec:** `docs/superpowers/specs/2026-10-12-reson-foundation-design.md`

## Global Constraints

- Target arm64 macOS 14 or later initially.
- One Rust engine crate; do not introduce empty library or core crates.
- No browser engine, accounts, telemetry or runtime network calls.
- File opening, probing and audio setup occur on the worker, outside the main UI thread.
- The command queue is bounded; enqueueing never waits for decoder completion.
- No Swift callbacks from audio callbacks, and no Rust panic crosses into Swift.
- Unknown metadata is displayed as unavailable, not guessed.
- SQLite, indexing, playlists, gapless playback and output-device selection are deferred.
- No bit-perfect or strict real-time claims before verification.
- Use original styling; no invented library records or generated artwork.

## Review Focus

1. Rapid A→B loads must not show A's metadata as B's; exercise replacement ordering in Task 1 and live replacement in Task 4.
2. Unicode paths and paths containing spaces must load without shell interpretation; exercise bridge copying in Task 3 and native opening in Task 4.
3. Truncated audio, inaccessible files and missing output devices must produce recoverable errors; exercise decoder/worker errors in Task 2.
4. Quit during load or playback must release resources without handle races; exercise shutdown in Task 3 and native quit in Task 4.
5. EOF, paused state and stop must update controls and terminate unnecessary polling; exercise state transitions in Task 1 and UI refresh in Task 4.

---

## File responsibilities

- `Cargo.toml`, `crates/engine/Cargo.toml`, `Cargo.lock`: workspace, static-library configuration and pinned dependencies.
- `crates/engine/src/lib.rs`: public Rust modules.
- `crates/engine/src/state.rs`: playback states, snapshots and transitions.
- `crates/engine/src/playback.rs`: backend, metadata probing and worker commands.
- `crates/engine/src/ffi.rs`: C boundary, pointer validation and text copies.
- `macos/Bridge/include/reson.h`, `macos/Bridge/include/module.modulemap`: C API and Swift import.
- `macos/Package.swift`: native executable and bridge linkage.
- `macos/App/ResonApp.swift`, `PlayerModel.swift`, `EngineBridge.swift`: scene, observable UI state and serialized handle ownership.
- `macos/Views/ContentView.swift`, `TrackTable.swift`, `InspectorView.swift`, `TransportView.swift`: window composition, AppKit table, selected metadata and playback controls.
- `macos/Info.plist`: application metadata.
- `scripts/build.sh`, `scripts/run.sh`: release build, app packaging and launch.
- `tests/fixtures/README.md`, `crates/engine/tests/decoder.rs`, `ffi.rs`: fixture provenance and integration tests.
- `.gitignore`, `README.md`, `docs/audio-path.md`, `docs/benchmarks.md`: repository hygiene, usage, output limitations and measurement protocol.

### Task 1: Testable playback states and Rust workspace

**Produces:** `PlaybackState` with stable discriminants Empty=0, Loading=1, Playing=2, Paused=3, Stopped=4, Ended=5, Error=6. `Snapshot { generation: u64, state: PlaybackState, position_seconds: f64, duration_seconds: Option<f64>, path: String, title: String, artist: Option<String>, album: Option<String>, sample_rate: Option<u32>, channels: Option<u16>, bit_depth: Option<u16>, format: String, error: Option<String> }`. `Command { Load(PathBuf), Play, Pause, Stop, Shutdown }`.

- [ ] Create workspace manifests, module declarations and focused state tests before implementation. Tests: `pause_resume_preserves_position`, `stop_resets_position_retains_path`, `ended_play_restarts`, `valid_load_recovers_error`, `replacement_generation_rejects_stale_result`. Assertions follow the states and position semantics in the spec.
- [ ] Run `cargo test -p reson-engine --lib`; confirm the new behavioural tests fail before implementing transitions.
- [ ] Implement the state model in `state.rs`; define generation advancement on load and reject completion snapshots for older generations. Add `.gitignore` for Cargo/Swift build outputs and packaged apps.
- [ ] Run `cargo test -p reson-engine --lib` and `cargo fmt --all -- --check`; require all state tests and formatting to pass.
- [ ] Commit the workspace and model as `feat: establish playback state model`.

### Task 2: Decoder and worker-owned audio output

**Consumes:** Task 1 states and commands.

**Produces:** `Engine::new() -> Result<Engine, EngineError>`, `Engine::send(&self, command: Command) -> Result<(), EngineError>`, `Engine::snapshot(&self) -> Snapshot`, `Engine::shutdown(&mut self) -> Result<(), EngineError>`. `probe(path: &Path) -> Result<TrackInfo, EngineError>` supplies source properties without full-file decoding. `TrackInfo` contains the path/title/artist/album/format/sample_rate/channels/bit_depth/duration_seconds fields and types from Task 1's Snapshot. `EngineError` distinguishes invalid input, I/O, decoding, output, queue full, disconnected and worker panic.

- [ ] Resolve the rodio release from primary documentation and inspect its source. Select only required codec/output features, commit the lockfile, and record callback decoding, allocation and locking behaviour in `docs/audio-path.md`. If unacceptable blocking is identified, present the worker-decoded PCM backend change before implementation claims.
- [ ] Create generated 16/24-bit mono/stereo PCM WAV and FLAC fixtures at 44.1/48 kHz. Document generator commands, deterministic sample values and provenance. Keep generation tooling out of runtime dependencies.
- [ ] Write `decoder.rs` tests: `fixture_properties_match_headers`, `decoded_samples_match_reference`, `malformed_input_returns_error`, `missing_path_returns_error`. Check format, channels, rate, bit depth where reported, and decoded reference samples with explicit tolerances for floating conversion. Run `cargo test -p reson-engine --test decoder` and confirm failure before adding decoder/probe implementation.
- [ ] Implement probing and decoding via the chosen version's actual APIs. Capture format and duration only where reported, retain filename title fallback, and leave unavailable tags empty. Avoid reading artwork or decoding a whole file during probing.
- [ ] Write worker tests using a small private fake backend for `fifo_load_replacement`, `queue_full_returns_immediately`, `output_failure_then_valid_load_recovers`, `stop_drops_source_and_stream`, `shutdown_during_load_joins`, and `worker_panic_becomes_error`. Run these tests and confirm the missing worker behaviours fail.
- [ ] Implement the worker with a bounded command channel of capacity 16 and nonblocking `try_send`. Open output lazily, serialize commands, own stream lifetime, detect EOF while active, and block waiting when stable/idle. Preserve pause position; recreate playback from zero after stop/end. Snapshot locks never occur in application audio callbacks. Document unavoidable dependency callback behaviour accurately.
- [ ] Run `cargo test -p reson-engine`, `cargo clippy -p reson-engine --all-targets -- -D warnings`, and `cargo build -p reson-engine --release`; require successful tests/lint/build. Record source versus configured stream format separately.
- [ ] Commit as `feat: add worker-owned lossless playback`.

### Task 3: Minimal C bridge with explicit ownership

**Consumes:** Task 2 `Engine` API.

**Produces:** Opaque `ResonEngine`; exported `reson_engine_create`, `reson_engine_destroy`, `reson_engine_load`, `reson_engine_play`, `reson_engine_pause`, `reson_engine_stop`, `reson_engine_snapshot`. All statuses are `int32_t`: OK=0, InvalidArgument=1, QueueFull=2, Disconnected=3, BufferTooSmall=4, InternalError=5. Asynchronous playback errors live in snapshots.

`create(ResonEngine **out)` reports initialization status. `load(ResonEngine *, const uint8_t *path, size_t length)` copies a validated UTF-8 path. Play/pause/stop take a handle. `destroy(ResonEngine *)` joins shutdown and consumes the handle. No calls may overlap destruction. Null destroy is a no-op; a freed handle must never be reused.

`snapshot(ResonEngine *, ResonSnapshot *out, uint8_t *text, size_t capacity, size_t *required)` copies scalars and a NUL-terminated UTF-8 JSON text payload containing path/title/artist/album/format/error. Required capacity includes the terminator. Null text with zero capacity queries size. `ResonSnapshot` has `uint64_t generation`, `uint32_t state`, doubles `position_seconds`, `duration_seconds`, and `uint32_t sample_rate`, `channels`, `bit_depth`; unknown duration is -1 and unknown integer fields are 0. The JSON choice keeps ownership simple without expanding the initial ABI for each tag.

- [ ] Write integration tests for null arguments, invalid UTF-8, zero-capacity sizing, undersized buffers, Unicode/path copying, state discriminants, snapshot fields and repeated create/destroy. Assert borrowed path bytes can be changed after load returns without changing the queued path. Run `cargo test -p reson-engine --test ffi` and confirm failure before exports exist.
- [ ] Implement `ffi.rs` and the header/module map with matching fixed-width types. Validate pointers before access, never expose Rust strings, and contain panics at each export. Use serde_json only for the small non-audio snapshot text payload; document this dependency and its role.
- [ ] Test destruction after queued load and playback state changes. Keep the unsafe handle contract explicit; do not test undefined use-after-free as if recoverable.
- [ ] Run `cargo test -p reson-engine`, then compile a small C header check with `clang -fsyntax-only -x c macos/Bridge/include/reson.h`; require both to pass.
- [ ] Commit as `feat: expose owned playback engine through C ABI`.

### Task 4: Packaged native window and playback interaction

**Consumes:** Task 3 header and snapshots.

**Produces:** `EngineBridge` owns one handle on a serial dispatch queue; async load/play/pause/stop/snapshot/shutdown calls never run worker joins on the main actor. `@MainActor PlayerModel` owns opened session tracks, selected path, latest playback snapshot, error display and refresh scheduling.

- [ ] Create the Swift package and `scripts/build.sh` linking the arm64 Rust static library. Set a macOS 14 deployment target for Rust and Swift, build release artifacts, and copy the executable/Info.plist into `build/Reson.app`. `scripts/run.sh` builds if needed and opens that app. Locate tools through PATH, quote paths and do not embed developer-specific absolute paths.
- [ ] Implement `EngineBridge.swift` with serialized handle calls, two-pass snapshot buffer sizing, finite buffer-too-small retry, scalar/JSON decoding and idempotent shutdown. Implement `PlayerModel.swift` generation-aware acknowledgement, session-file metadata and separate selection/current-playback state.
- [ ] Implement the window at 1180 × 740 default, 820 × 520 minimum, dark appearance, native translucent sidebar and collapsible inspector. Use NSTableView for actual opened files; show missing tags as em dashes and filenames as fallback titles. Planned sidebar destinations are visibly unavailable.
- [ ] Implement NSOpenPanel for FLAC/WAV, Command-O, row double-click playback, Space with text-focus protection, and menu commands for sidebar/inspector. Transport has play/pause, stop and elapsed/duration only; no functional-looking unsupported controls. Show worker errors visibly with retry through Open/Play.
- [ ] Refresh at 4 Hz during loading/playback or pending commands. Stop refresh after stable paused/stopped/empty/error acknowledgement. Observe native termination, serialize handle teardown and let shutdown finish off the main actor before final termination.
- [ ] Run `scripts/build.sh`; require a release `.app` with an arm64 executable. Confirm with `file build/Reson.app/Contents/MacOS/Reson` and `plutil -lint build/Reson.app/Contents/Info.plist`.
- [ ] Use available native UI tools to launch and inspect the app. Exercise fixture opening, Unicode/spaced paths, rapid A→B replacement, pause/resume, stop/restart, EOF, error recovery, selection versus current track, panel toggles, minimum-size resizing and quit during load/playback. Record observed results; do not equate screenshots with audible verification.
- [ ] Commit as `feat: add native macOS playback window`.

### Task 5: Audio checks, baseline protocol and user documentation

**Consumes:** Working package and test suite.

**Produces:** Reproducible build instructions, validation record, audio limitations and benchmark protocol.

- [ ] Run a live default-device playback test for representative FLAC and WAV. Verify pause/resume and stop through actual output with listening or available loopback recording. Mark any unverified audible-output check explicitly and keep it open as an acceptance gap.
- [ ] Finish `docs/audio-path.md`: pinned backend/version, source/sample conversion, configured stream properties, unverified hardware/mixing behaviour, callback inspection findings and supported versus tested formats. Do not claim bit-perfect output or precise timing from decoder tests.
- [ ] Write `docs/benchmarks.md` with fixed release build/files, hardware/OS/device/rate, ten startup trials, 60-second settled idle samples and 60-second playback samples repeated three times. Use Instruments or native process tooling for CPU/memory; distinguish cold and warm startup and record measurement overhead. Indexing measurement is explicitly deferred.
- [ ] Write README prerequisites, `scripts/build.sh`/`scripts/run.sh`, dependency download versus cached offline build instructions, implemented/planned list, FFI ownership/threading summary, errors and validation results. Propose MIT for original code without claiming the license has been chosen; document dependency licenses and fixture provenance.
- [ ] Run final `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, and `scripts/build.sh`. Repeat native interaction checks only if changes affect them. Record exact passed checks and remaining gaps.
- [ ] Commit as `docs: document builds audio behaviour and performance checks`.

## Execution and completion

Plan review and execution-method selection precede product implementation. Recommend native execution in this chat because the five deliverables share a narrow, evolving ABI and output-backend integration. If a skill requires independent review, use its prescribed reviewer at the appropriate gate; do not dispatch parallel implementers against these shared files.

At execution start, inspect repository/worktree state and use the worktree skill if isolation is needed. Keep commits local; no publication or push is part of this request. Report the packaged app path, build/run instructions, observed validation and material limitations. Keep audible playback as an explicit unresolved item if it cannot be confirmed.
