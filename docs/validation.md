# v0.1 validation record — 13 October 2026

Performed locally on arm64 macOS with Rust 1.99.0 (Homebrew), Swift 6.4 and Xcode. No push, publication or external service was used.

## Automated and build checks

- 25 Rust tests: 16 state/worker, 5 decoder/metadata, 4 FFI tests. All passed.
- 2 Swift acknowledgement/generation tests. Passed.
- cargo fmt check, clippy with warnings denied, C header syntax, release Rust/Swift app build, plist lint and arm64 executable identification passed.
- Build warnings remain: the host's prebuilt Rust standard library targets macOS 27, while the project requests macOS 14. Older-OS compatibility is unverified; this is not a warning-free distribution build.

The initial state, decoder, worker and FFI test runs failed because their APIs did not yet exist. Behavioural regressions additionally failed before fixes for fixed output buffers, lost metadata after output failure, WAV tag padding and command blocking during output teardown. Swift's initial test invocation failed because the app target did not yet exist.

## Live engine

The default output was AirPods Pro. Both 30-second, 24-bit stereo 44.1 kHz WAV and FLAC reached Playing. Reported output stream: 48 kHz, two channels, F32. Pause/resume, frozen paused position, stop/reset, restart, short-file EOF, missing-file recovery and shutdown passed in `examples/live_check.rs`.

The first attempt failed because rodio selected Fixed(2048) but the device supported only 15..960 frames. Using the OS default buffer resolved setup failure. This checks actual stream creation and source consumption; it does not verify the physical output waveform.

## Native UI

Inspected the actual packaged window and native picker. Verified Command-O, Unicode/spaced paths, WAV/FLAC table metadata, play/pause state, stop/reset, restart with Space, double-click, rapid FLAC→WAV replacement, sidebar/inspector toggles, selection distinct from current playback, and quitting during playback (process exited). WAV tag padding exposed by native inspection is fixed and covered by a decoder regression.

The native picker rejected the malformed fixture before engine loading; malformed/missing file handling and recovery were exercised through Rust and the live engine instead. The native minimum-size drag could not be confirmed through available automation, so compact-window resizing QA remains unverified. Rapid in-flight replacement is also checked deterministically using a gated backend test.

## Acceptance gaps

- Audible output was not independently confirmed by listening or loopback capture. No audio-path precision/bit-perfect claim.
- Minimum-size native resizing and quit during a genuinely stalled filesystem operation remain unverified.
- macOS 14–26 runtime compatibility needs a compatible standard-library build and testing on those systems.
- No performance baseline measurements yet; see the reproducible benchmark protocol.
- Rodio performs file reads/decoding, allocation and locking in its callback path. Strict real-time guarantees remain unmet in this prototype.
