# v0.4 validation

Validation on 14 October 2026, on the development Apple Silicon Mac, against merged v0.3 (`b3d7dc56f743f5fcf130128eaa363e060c76ec37`). The initial checkout was clean. Work uses `reson-v0.4`, with no database migration: schema remains 2. Only original synthetic audio, generated metadata databases and isolated cache/preferences were used. Personal music was not opened or modified.

## Automated checks

The final required gates are `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, `./scripts/build.sh` and `(cd macos && swift test)`. Rust: **75 passing tests**. Swift: **73 discovered, 66 passing and seven default opt-in skips**. The native CoreAudio group passes separately (five tests, including the existing bridge/playlist journey); the existing synthetic playlist benchmark passes separately. Two unrelated artwork workload/maintenance timing tests were not rerun; their ordinary functional tests pass.

The C header also passes `clang -fsyntax-only -x c`, and the packaged plist passes `plutil -lint`. Build logs retain the existing Rust-standard-library/macOS-27 target warnings; they are not evidence of compatibility with older systems.

New coverage includes offline 44.1 kHz mono → 48 kHz stereo resampling/channel adaptation against hand-checked sample values, WAV/FLAC reference-sample seeking, frame rounding and bounds, nonfinite inputs, paused semantics, rapid requests, stale generations, Stop/replacement during in-flight seek, failed-seek recovery, retired source/callback fencing, terminal shutdown, gain bounds/mute restoration, repeated device replacement/resource release, C control validation, scrub display isolation/cancellation after replacement, native arrow-key actions, disabled duration, output selection/conversion presentation, persisted settings before lazy engine creation, and saved zero gain without accidental unmute. Existing EOF, history, queue duplicate/priority, artwork, native layout and SQLite migration/recovery suites remain intact.

Test-first failures caught a one-frame seek rounding boundary, the native keyboard action path, continued old-drag events after replacement, and a saved-zero-volume initialization accidentally restoring positive gain. These are fixed and their regression tests pass. A benchmark attempt initially lacked its required playlist seed, and a relative benchmark source path failed linkage; fixture initialization and path resolution were corrected and those tools rerun. No unresolved failing check is accepted for merge.

## Native application journey

The smoke application uses a source copy under ignored `build/v0.4-smoke`, a dedicated bundle identifier, `RESON_LIBRARY_PATH` database, temporary artwork cache and a separate UserDefaults suite. The window journey used the milestone engine and transport with test isolation paths/settings. The subsequent gain-reconciliation refinement was validated through the real native model/bridge burst test; its interactive rerun was unavailable after the Mac locked.

The application imported Amber.flac, Blue.wav and Short.wav, all original synthetic signals. Native accessibility interactions verified FLAC playback, paused forward/backward seeking, WAV seeking, rapid successive requests, gain decrement, mute/unmute, source/output details, explicit speaker selection and System Default restoration while retaining paused position. Actual popover values showed mono 16-bit 44.1 kHz source feeding a stereo 48 kHz F32 stream. A nonfatal xrun appeared during desktop/build load without halting playback.

The native journey also created Audio Checks, added three library rows, played its sequence, exercised Next/Previous, enqueued Play Next, observed natural EOF consume queued playback, and verified Stop/reset/restart. Search and sorting while Blue played preserved its sequence. Selecting Amber displayed green inspector artwork while the paused Blue transport remained blue. Quit/relaunch preserved three library records, the three playlist entries, cached artwork and gain/mute preferences. System Default was selected on relaunch. Final native quit exited cleanly; SQLite integrity was `ok`, foreign-key checks were empty, and schema was 2.

The computer-use server supported accessibility interaction and screenshots but repeatedly returned `noWindowsAvailable` for coordinate dragging. Therefore literal pointer drag/click-to-seek and full keyboard traversal were not manually certified. The Mac subsequently locked, preventing another interactive pass; the final gain-reconciliation policy is additionally tested through the real native model/bridge. The remaining isolated smoke process was terminated after the lock, distinct from the earlier verified native clean quits. Native NSSlider action/key tests and deterministic drag-state tests cover those paths; real native accessibility changes reached the engine and retained pause. Compact 820×520 and normal 1180×740 layouts pass native hosting tests. This automation limitation is distinct from a reproduced playback failure.

## Real CoreAudio and resources

The native integration group exercised both codecs, seek forward/backward/beginning/near-end, pause/resume, app gain/mute, 20 explicit/default switches, unavailable-ID failure, explicit recovery paused at the retained cursor, seeking after recovery, Stop and terminal bridge closure. The original `live_check` additionally passes WAV/FLAC pause/resume/stop/restart, natural EOF, file-error recovery and shutdown. Queue/history/duplicate/rapid-replacement integration passes with actual output streams.

Two physical outputs were available: AirPods and built-in speakers. Both were used by the native journey; repeated benchmark switching pins the enumerated AirPods output versus System Default. The aggregate DJ output was enumerated but not validated. Physical unplug and OS default-route changes were not induced. Deterministic CPAL-event tests verify DeviceChanged/Xrun/RealtimeDenied remain nonfatal, fatal disconnects halt progression, and retired callbacks cannot fail replacement streams. A deliberately nonexistent device ID verifies real build failure and paused recovery without silently falling back.

CoreAudio read-only volume scalars were `[0.5625, 0.5625]` in the earlier pass and `[0.0625]` in the later pass, unchanged within each pass before/after gain/mute/device tests. These are separate device/environment observations, not a cross-run volume comparison. No global output, rate or volume setting was written. No audible listening, loopback, exclusive-mode or bit-perfect output evidence is claimed.

After settling 200 ms, the release audio benchmark observed **10 threads / 13 lsof entries** before switching, after 30 switches and after 60 switches. After terminal shutdown: **5 threads / 12 entries**. These are process-wide counts, not a direct count of CoreAudio stream handles. The backend owns at most one stream; deterministic replacement tests count every retirement. No accumulation was found in these runs. Commands are bounded to 16 and each stream has separate bounded fatal/notice channels. A 40-command native gain burst during output replacement exercised backpressure: the UI, engine and saved preferences agreed on the accepted gain (approximately 0.384615), and two queued occurrences remained untouched. Rejected optimistic controls reconcile to acknowledged engine values. New idle activity consists of one asynchronous enumeration and a blocked playback worker; there is no enumeration timer or idle snapshot loop.

## Seeking and control measurements

Release `audio_bench` uses 30 operations per codec/gain case, ten enumerations, 30 timed switches plus another 30 for stability, and 15 direct stream lifecycle measurements. Acknowledgement timing includes a 1 ms observer sleep, so it is an upper-bound observation rather than pure worker execution time. Fixtures are eight-second silent stereo 44.1 kHz sources.

| Operation | Median / p95 ms |
| --- | ---: |
| WAV decoder construction | 0.021 / 0.036 |
| WAV prepare + seek | 0.025 / 0.180 |
| FLAC decoder construction | 0.018 / 0.022 |
| FLAC prepare + seek | 0.034 / 0.039 |
| WAV and FLAC worker seek acknowledgement | 1.255 / 1.259 |
| Gain acknowledgement | 1.256 / 1.260 |
| Output enumeration | 0.929 / 1.413 |
| Output switch acknowledgement | 63.998 / 109.040 |
| Direct stream open | 47.494 / 54.505 |
| Direct stream destruction | 30.372 / 59.020 |

Final Swift bridge/native seek acknowledgements were approximately **3.0–3.5 ms**. Paused reported targets matched within one source frame (22.7 µs at 44.1 kHz; 20.8 µs at 48 kHz). Reference decoded samples match exact hand-checked PCM values for 16-bit mono WAV/FLAC at 44.1 kHz and 24-bit stereo WAV/FLAC at 48 kHz. These fixtures check decoder accuracy, not when a DAC presents a seek. Large/slow files and device-buffer latency were not exhaustively characterized.

## Transitions and gapless investigation

Original 0.2-second nonzero boundary markers are generated in WAV/FLAC at 44.1 kHz, with a 48 kHz marker for differing-format transitions. The benchmark mutes these signals. It measures observed EOF to next load acknowledgement using immediate worker commands; Swift coordination is measured separately with queue duplicates/priority.

| Measurement | Median / p95 ms |
| --- | ---: |
| Same-format observed EOF → next load acknowledgement | 64.055 / 69.504 |
| Different-format observed EOF → next load acknowledgement | 61.437 / 65.069 |
| EOF observation after nominal 200 ms source duration, same format | 110.001 / 115.236 |
| EOF observation after nominal source duration, different format | 111.820 / 412.073 |

The high differing-format p95 illustrates scheduling/device variability, not a codec startup problem. Separate decoder preparation is tens of microseconds; stream teardown/open and the 100 ms EOF observation interval are larger costs. The Swift model's initial post-change intervals between acknowledged track starts were **402–411 ms** for these 200 ms tracks, including duplicate queue occurrences and a differing-format transition. A later all-native run observed 821–1,026 ms intervals after repeated switching, demonstrating hardware/scheduling variability. Before the contained near-EOF refresh adjustment, corresponding observed intervals were **503–508 ms**. The final UI tightens its existing refresh cadence from 250 to 100 ms only near EOF or while awaiting a command; paused/idle behavior remains economical. These observations are not a captured DAC-gap measurement or a guaranteed speedup.

True gapless is deferred. The architecture closes the stream at EOF, waits for Swift completion coordination and then initializes another output. Guaranteeing sample continuity would require preparing the next occurrence and retaining/scheduling the stream before EOF, with explicit queue ownership contracts. No such speculative rewrite, crossfade or unbounded PCM buffer was added. A later isolated audio benchmark recorded switch acknowledgement 572.433 / 673.778 ms, same-format EOF-to-load 596.039 / 729.538 ms, differing-format 583.085 / 651.423 ms and stream open 530.481 / 586.518 ms (median / p95). An identical direct rodio/CPAL tool that bypasses Reson control/seek logic reproduced slow opening in both v0.3 (504.487 / 554.643 ms) and v0.4 (478.639 / 579.048 ms). This supports attributing the variable cost to shared output lifecycle/environment rather than a new seeking regression; the exact CoreAudio cause remains unidentified. The following isolated Swift transition test returned to 403–407 ms start intervals. Source markers make a future loopback test reproducible, but sample-level output continuity was not captured in this environment.

## Footprint, startup and library performance

The documented v0.3 executable was 3,614,560 bytes. A fresh v0.3 production source copy built in this session measured **3,636,408 bytes**; the difference reflects build/path conditions and prevents treating the earlier number as an exactly matched baseline. The final production v0.4 executable is **3,879,712 bytes** (**+243,304 bytes**, **+6.69%** relative to the fresh baseline). No new dependencies were added.

The paired startup tool archives the version-matching baseline source/archive, instruments only ignored source copies, backs up identical schema-2 synthetic databases and launches each version six times per case. First launch is excluded; remaining five warm medians are reported. Window-ready is an application marker, not finished compositing. CPU is sampled over ten seconds after a three-second settling period. Both copies preserve track count/ID range/sum, foreign keys and integrity. No cold-cache claim is made.

| Tracks | Window v0.3 / v0.4 ms | Library v0.3 / v0.4 ms | Idle CPU v0.3 / v0.4 | RSS v0.3 / v0.4 KiB |
| ---: | ---: | ---: | ---: | ---: |
| 270 | 169.0 / 178.8 | 246.5 / 261.9 | 0.1% / 0.0% | 111,232 / 130,864 |
| 5,000 | 157.8 / 170.0 | 269.2 / 309.5 | 0.1% / 0.0% | 108,096 / 137,184 |
| 25,000 | 163.3 / 168.1 | 428.8 / 471.0 | 0.0% / 0.0% | 83,296 / 129,296 |

Warm readiness increases in the final paired run are roughly 15–42 ms. Earlier runs varied materially; idle RSS also varies with compression/framework state and desktop scheduling. There is no established memory reduction or startup speedup claim. The measured increase is accepted for native transport controls and audio-device diagnostics; one-time enumeration starts the otherwise blocked playback worker. The engine still opens streams only on playback.

A separate identical headless three-second silent-playback observation recorded v0.3/v0.4 CPU **1.659% / 1.326%**, RSS **17,680 / 17,648 KiB**. It excludes SwiftUI and is too short/noisy to establish a speedup. No accumulated background polling was introduced.

Library browse/search results at 25k remained approximately 0.267 / 4.856 ms. The existing playlist/native table benchmark passes at 270/5k/25k. The 25k debug-run enqueue/move/clear measured 13.60 / 32.60 / 0.72 ms, selected playlist edit+reload 359.29 ms and maximum main-actor heartbeat gap 3.27 ms. These debug measurements are not compared as speedups to v0.3 release results. Native table cells remained correct after scrolling; ordinary library/playlist behavior is covered by the complete suites.

## Reproduction and unavailable checks

```sh
python3 scripts/generate-v0.4-fixtures.py build/v0.4-audio
RESON_AUDIO_FIXTURES="$PWD/build/v0.4-audio" RESON_NATIVE_PLAYBACK_TEST=1 \
  swift test --package-path macos --filter 'AudioRefinementIntegrationTests|TransitionIntegrationTests|PlaylistIntegrationTests'
cargo run --release -p reson-engine --example live_check -- build/v0.4-audio/silent.wav build/v0.4-audio/silent.flac
cargo run --release -p reson-engine --example audio_bench -- build/v0.4-audio
cargo run --release -p reson-engine --example playback_cpu_bench -- build/v0.4-audio/silent.wav
cargo run --release -p reson-engine --example stream_bench
cargo run --release -p reson-engine --example library_bench -- build/v0.4-bench/library
cargo run --release -p reson-engine --example playlist_bench -- build/v0.4-bench/library
RESON_PLAYLIST_BENCHMARKS="$PWD/build/v0.4-bench/library" \
  swift test --package-path macos --filter PlaylistBenchmarkTests
```

For paired startup, archive the baseline commit into `build/v0.4-baseline/src`, build its matching Rust static archive into that source copy's `target/release/libreson_engine.a`, build current with `scripts/build.sh`, then run:

```sh
python3 scripts/benchmark-v0.4-startup.py build/v0.4-bench/library build/v0.4-baseline/src
```

Raw logs live in ignored `build/v0.4-{rust-final,clippy-final,build-final,swift-final,native-final,native-live,audio-bench,baseline-cpu,current-cpu,library-bench,playlist-bench,startup-isolated}.log`, plus `build/v0.4-{audio-bench-final,transition-final,baseline-stream,current-stream}.log`. Generated audio, source copies, databases, apps and logs are not committed. Reproduction tools are committed.

Final failing checks: none. Skipped after separate opt-in runs: unrelated artwork workload/maintenance timing. Unavailable/unverified: literal native pointer dragging through this computer-use server, full manual keyboard traversal, physical unplug/default-route changes, captured continuity, listening, hardware precision and execution on macOS 14–26. Inherited callback decoding/file I/O/allocation/locking and potentially unbounded file/device shutdown stalls remain documented limitations.

The feature branch is preserved. No release tag, GitHub Release or visibility change is part of this milestone.
