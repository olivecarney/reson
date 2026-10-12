# v0.1.1 maintenance validation

13 October 2026. Native execution and self-review; no subagents, dependency additions, backend replacement or C ABI changes. This is a maintenance update, not a new feature milestone.

## Changes

- **Terminal bridge lifecycle:** a queue-owned `closed` flag is set before destruction. Engine creation, commands and snapshots reject requests after shutdown with `BridgeError.closed`. Shutdown is idempotent; the handle is cleared before its one destruction. Queued operations retain the bridge only until execution completes. The deinit fallback captures the remaining handle, never the bridge, and destroys it on the background serial queue.
- **Paused output health:** the worker uses a 500 ms receive timeout while an output stream is paused, keeping the existing 100 ms playing timeout. Healthy paused polls never advance position. A failed backend transitions to Error and releases resources; replay or a fresh load can recover. With no active stream the worker still blocks indefinitely. Swift checks paused snapshots once per second to make that error visible without resume; loading/playing checks remain 4 Hz. There are no extra worker threads or synchronization primitives.
- **AppKit reuse:** every column has a stable reuse identifier. `makeView(withIdentifier:owner:)` supplies reusable image/text cells. Views and constraints are created only when reuse is unavailable. Content, font, color and artwork are reset on each assignment.
- **Reload scope:** comparison now uses only displayed table values. Transport-only changes cause no reload; metadata changes reload affected rows. Insertions/removals/order changes retain the simple full reload. Selection is restored by path and programmatic reload notifications do not overwrite it. No generic diffing framework or cache was introduced.
- Engine/app version metadata is 0.1.1, including the sidebar label. Original controls, layout and columns are preserved.

## Regression evidence

Tests were added before fixes. The old bridge failed terminal-shutdown tests and the old worker failed paused-failure/modest-check tests. The old table failed object-reuse assertions. A reload counter demonstrated full reloads for transport-only snapshot changes and no targeted row update before the fix.

After fixes, all **28 Rust tests** and **9 Swift tests** passed. Added coverage includes shutdown before first engine creation, repeated/concurrent shutdown, post-shutdown commands/snapshots, deinit without a retain cycle, paused failure/replay/fresh-load recovery, frozen paused position, modest check frequency and no-stream zero polling. Table tests exercise content/style resets, unchanged constraints, artwork reuse, reload counters, selection across structural updates, and actual AppKit scrolling through 100 synthetic rows and back.

Required commands passed:

```sh
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/build.sh
(cd macos && swift test)
```

The host's Rust standard-library macOS 27 deployment warnings remain when linking for macOS 14. No new compile errors or clippy warnings were introduced. Older macOS runtime compatibility remains unverified.

## Live and native integration

The live engine example passed WAV/FLAC play, pause, resume, stop/reset, restart, EOF, missing-file recovery and shutdown on the default device. Source format remained 24-bit stereo 44.1 kHz; configured output remained 48 kHz stereo F32.

In the native window, checked file opening, WAV/FLAC cells, pause/frozen position/resume, stop, selection versus playback, inspector details, double-click and rapid FLAC→WAV replacement. An actual output error occurred during native setup/playback and retrying Play recovered. Quit during playback terminated the process. High-row-count scrolling/reuse was verified in the AppKit test harness; the session window contained two real synthetic audio files.

Paused output failure was injected with the existing fake-backend pattern rather than deliberately disconnecting or switching the user's device. Physical paused-device disconnection and audible output/loopback capture were not verified.

## Idle sanity check and review

Coarse five-second process CPU-time samples observed 0.00 CPU seconds for the previous inactive build and 0.01 CPU seconds for the maintenance build (about 0.2% of one core over that interval). These short samples, different session contents and 0.01-second counter granularity do not constitute a rigorous benchmark; they revealed no obvious busy loop. The deterministic tests additionally confirm no backend polling in empty/stopped states and a bounded paused check count. Full performance profiling remains future work.

Self-review checked queue ownership and deinit lifetime, every worker stream-active transition, generation guards, pause position handling, all displayed cell values, structural reloads and selection handling. No additional blockers were found. Existing rodio callback decoding/locking and output-precision limitations remain as documented in audio-path.md.
