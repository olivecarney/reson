# v0.3 validation

Validation performed on the development Apple Silicon Mac on 13–14 October 2026, against merged v0.2.2 (`d0aa1d86ba8e5491a0c2ee7a731716ad23065629`). Only original synthetic audio and isolated SQLite/cache directories under ignored `build/` were used. No user music library was opened or modified.

## Automated evidence

Final gates: `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, `./scripts/build.sh`, and `swift test --package-path macos`. Rust: 62 tests. Swift: 59 discovered, 55 passed and four opt-in skips in the default run. The two real bridge/CoreAudio integration tests additionally pass with `RESON_NATIVE_PLAYBACK_TEST=1 swift test --package-path macos --filter PlaylistIntegrationTests`. The opt-in playlist performance test passes separately.

Coverage includes transactional v1 migration/reopen, process kill during uncommitted schema DDL, failed insertion/reorder rollback, CRUD, duplicates, dense ordering, missing/restored/rescanned paths, stale/reused track IDs, invalid requests, C buffer ownership, import cancellation and terminal shutdown. Playback tests cover EOF versus Stop/output failure, repeated/stale completion, rapid replacement, queue priority/duplicates/clear/remove/reorder, confirmed Previous history, bounded invalid-file skipping and selection independence. Native NSTableView/NSPasteboard tests exercise multiselection, sidebar drop targets, entry identity, menus, keyboard moves and selection repair. M3U8 tests cover Unicode, symlink-relative paths, URI rejection, invalid UTF-8, malformed metadata, unsafe export paths, exclusive temporary collisions and round trips.

## Native journey

The isolated app imported three original synthetic FLAC/WAV tracks, created Morning and Evening playlists, added multiple rows by native drag/drop and dragged Short ahead of Amber/Blue. Rename, double-click playback, Next/Previous controls and shortcuts, natural EOF, Play Next, Add to Queue, queue presentation, keyboard reorder, single-occurrence removal and clear all worked. Queue drag delegate behaviour is automated; coordinate-based sheet dragging did not provide reliable manual evidence.

Switching lists/search and selecting Blue while Amber played preserved the captured sequence and showed blue inspector artwork alongside green transport artwork. M3U8 export/import retained order and duplicate Blue entries. Removing the playing Amber entry did not interrupt audio. Rescan during playback retained the sequence. A priority Blue item began at EOF and was consumed exactly once; clearing pending items while paused preserved position. Delete cancellation retained a playlist, and confirmed deletion removed it. Stop reset position; native quit and relaunch restored persistent playlists and artwork. SQLite integrity/foreign-key/order checks passed.

The file named **Amber.flac actually embeds a solid green PNG**, RGB (55,140,80). Direct extraction with ffmpeg confirms this. Its green cover is correct; the synthetic filename was misleading. Blue.wav embeds a blue APIC image. Artwork is determined by embedded bytes, independently of the filename.

Real output-stream integration verified queue sequence a,c,c,b,b,c, history, rapid replacement and Stop immediately after Load. Synthetic smoke audio was silent. Audible output and bit-perfect output were not verified. A nonfatal xrun occurred under compilation/desktop load; no fatal stream failure was observed in the smoke journey.

## Size and startup

Production executables built serially: baseline 2,998,288 bytes; v0.3 3,614,560 bytes, +616,272 (+20.6%). No dependencies were added. Do not overlap release Swift tests and production builds: testing-enabled artifacts can otherwise affect executable-size measurements.

`scripts/benchmark-v0.3-startup.py` uses separately instrumented baseline/current source copies, version-matching Rust archives, isolated artwork directories and SQLite backups of schema-v1 fixtures. Six launches per case, first excluded; table reports five warm medians. Window-ready measures the application marker, not completed screen compositing. Readiness includes loading saved metadata. Current copies migrate to v2 with integrity OK and identical track ID count/range/sum.

| Tracks | Window baseline/current ms | Library baseline/current ms | Idle CPU baseline/current | RSS baseline/current KiB |
| ---: | ---: | ---: | ---: | ---: |
| 270 | 248.1 / 229.8 | 352.2 / 315.7 | 0% / 0% | 77,936 / 113,632 |
| 5,000 | 228.7 / 232.6 | 391.0 / 363.2 | 0% / 0% | 114,368 / 111,872 |
| 25,000 | 218.1 / 238.9 | 572.0 / 612.8 | 0% / 0% | 123,296 / 83,264 |

Idle CPU/RSS were sampled after three seconds, across a further ten seconds. Desktop scheduling and memory compression vary substantially. The final 25k readiness result is +40.8 ms (+7.1%); an earlier paired run was 475.1/470.6 ms. These are warm-run observations, not a statistically established speedup or memory-footprint claim. No cold-cache claim is made.

## Playlist and queue measurements

`cargo run --release -p reson-engine --example playlist_bench -- build/v0.3-bench/current` runs 30 queries/reorders per size. Query is one page (up to 500 entries); move changes three entry IDs across the list. Repeating the tool creates another benchmark playlist, so database deltas depend on existing allocation.

| Tracks | Query median / p95 ms | Move median / p95 ms |
| ---: | ---: | ---: |
| 270 | 0.226 / 0.425 | 0.557 / 1.750 |
| 5,000 | 1.046 / 1.844 | 5.992 / 8.057 |
| 25,000 | 2.556 / 3.764 | 34.099 / 42.552 |

Empty v2 tables add 16,384 bytes over v1 fixtures. First full playlist increased v2 DB size by 20,480 / 438,272 / 2,158,592 bytes at 270 / 5k / 25k. A subsequent benchmark run added 28,672 / 438,272 / 2,297,856 bytes. Existing library browse/search medians stayed close: 5k browse 0.276→0.283 ms, search 0.982→0.992; 25k browse 0.272→0.288, search 4.904→4.991.

`RESON_PLAYLIST_BENCHMARKS=.../build/v0.3-bench/current swift test -c release --package-path macos --filter PlaylistBenchmarkTests` measures actual model operations and reused native table cells. Batch queue enqueue includes all N tracks, unlike ordinary few-row user actions. Selected-playlist edit includes loading all its pages; background edits do not reload the whole library.

| Tracks | Enqueue / queue move / clear ms | Native scroll maximum ms | Edit + reload ms | Main-actor heartbeat max gap ms |
| ---: | ---: | ---: | ---: | ---: |
| 270 | 0.090 / 0.132 / 0.006 | 9.916 | 10.847 | 3.075 |
| 5,000 | 1.338 / 2.141 / 0.105 | 1.655 | 52.791 | 3.075 |
| 25,000 | 9.067 / 12.396 / 0.546 | 1.450 | 415.665 | 3.256 |

The first native-table case includes cold widget setup. Scroll values measure synchronous native scrolling/cell work, not frame presentation. The 25k edit and selected-playlist refresh take about 416 ms, with database work on the worker and paged presentation updates on the main actor; the heartbeat remains responsive. Reorder remains O(N); no constant-time claim is made. No significant unresolved interaction or idle-CPU regression was found.

## Limits and reproduction

Queue/history are session-only (history capped at 1,000). Visible lists are assembled from 500-row pages and captured using Swift copy-on-write storage when playback starts. Drag/edit commands cap selected IDs at 1,000; M3U8 caps 16 MiB/100k entries. Missing paths are retained but require explicit folder import to index. No automatic renamed-file detection or fingerprinting is provided. Filesystem/device stalls can delay background shutdown; no hard realtime claim is made.

The requested deployment floor remains macOS 14. This machine's Rust standard library emits macOS 27 target warnings; older-system execution remains unverified. Default CoreAudio output can resample; rodio callback decoding/allocation/locking remain existing limitations. Broader UX, seeking, output selection, gapless, shuffle and repeat are deferred.

Raw local logs live in ignored `build/v0.3-{rust,clippy,swift,native-integration}.log`, `build/v0.3-startup-final.log`, `build/v0.3-bench-playlists-final.log` and `build/v0.3-swift-bench-release-final.log`. Reproduction tools are committed; generated applications, databases, fixtures and logs are not. No release tag or GitHub Release is created by this milestone.
