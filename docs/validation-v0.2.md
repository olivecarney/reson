# v0.2 validation and measurements

Measured on Apple Silicon, macOS 27.0.1 / Apple SQLite 3.54.0, 2026-10-13. Local development builds, no push. Test-first red checks preceded the repository, worker, C ABI and native bridge implementations. Historical Turso results and commit are retained.

## Reliability

Final checks pass: 42 Rust tests and 12 Swift tests, cargo fmt, Clippy with warnings denied, native arm64 release build, C-header syntax and plist validation. The diagnostic Swift timing test is enabled by environment in a separate recorded benchmark run. Existing deployment warnings are documented below. Native executable contains no temporary readiness instrumentation.

System SQLite spike verifies bound Unicode/apostrophe paths, commit/rollback, UPSERT, schema version, JSON availability, reopen and independent sqlite3 integrity checks. SIGKILL before/after transaction commit preserves committed state and discards uncommitted state. A separate SIGKILL during a real Library worker import reopens the versioned store with committed progress and passes integrity_check.

Library tests cover stable IDs, repeat imports, updates, literal wildcard searches and injection-shaped strings, paging, each sort and stable ties, genre/BPM/key tags, Unicode/spaces, malformed input, cancellation retaining successes, missing/restored files, unavailable roots, symlink loops, newer versions and corrupt-database preservation. Worker tests browse and cancel between files, reopen and verify terminal shutdown. C ABI checks invalid arguments/JSON and caller-owned two-pass buffers. Swift tests import via C, close/reopen, and reject calls after shutdown. Existing playback replacement, queue, output failure and lifecycle tests remain intact.

Native UI checks used only ignored synthetic folders and an overridden test DB. Import showed two valid records and one skipped malformed WAV. Artist search and format-header sort worked. Double-click playback, selected-vs-playing inspector, restart without scanning, missing indicators after manual rescan and missing-file playback error worked. Direct mouse selection opened a valid FLAC and recovered playback. Go-to-file accessibility highlighting initially left Open disabled; direct mouse selection worked. Explicit picker configuration is retained. A 25,000-entry hardlink import completed while the 30-second synthetic FLAC played; large-library search worked. No audible listening/loopback or bit-perfect verification was performed.

## Footprint and latency

| Native executable | Bytes |
| --- | ---: |
| v0.1.1 | 2,196,672 |
| Minimal system SQLite spike | 2,224,560 |
| Turso spike, thin LTO | 15,968,368 |
| Full v0.2 library/UI | 2,723,792 |

The full app adds 527,120 bytes (24.0%) over v0.1.1 and remains 82.9% smaller than the Turso link spike. System spike adds 27,888 bytes (1.27%) to v0.1.1. otool verifies `/usr/lib/libsqlite3.dylib`; Cargo has no bundled SQLite or Turso dependencies. The full library adds code/UI beyond this minimal link spike. A copied executable stripped with `strip -S -x` is 1,904,976 bytes (v0.1.1: 1,580,944); the shipped local app retains its normal build symbols and signature.

Standalone open/schema/count/close: SQLite first 9.137 ms, warm median 0.9685 ms; Turso first 7.799 ms, warm median 0.6875 ms. Process wall SQLite first 26.743 ms/warm median 2.969 ms, Turso 3329.21 ms/5.124 ms. v0.1.1 has no database overhead. First runs are security/cache affected, not controlled cold startup.

Warm operation medians, 30 runs, parameterized queries with up to 500 copied rows. Metadata is synthetic, not 25,000 real songs. Turso 0.8.3 runs equivalent SQL over copied databases and consumes the same columns; it is a query comparison rather than a complete Turso native library implementation.

| Tracks | SQLite browse ms | Turso browse ms | SQLite search ms | Turso search ms | SQLite BPM sort ms | Turso BPM sort ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 270 | 0.1588 | 0.4188 | 0.0680 | 0.1589 | 0.2413 | 0.4027 |
| 5,000 | 0.2747 | 0.4905 | 0.9808 | 2.1571 | 0.7223 | 1.8480 |
| 25,000 | 0.2746 | 0.4800 | 4.8214 | 11.6030 | 2.0998 | 17.9908 |

| Tracks | Reopen + first page ms | All Rust pages ms | Closed DB bytes | Swift bridge first page ms | Swift warm search ms |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 270 | 0.764 | 0.162 | 102,400 | 6.930 | 0.113 |
| 5,000 | 0.655 | 3.694 | 1,122,304 | 9.791 | 1.321 |
| 25,000 | 0.740 | 35.271 | 5,537,792 | 8.410 | 7.016 |

270 real synthetic short WAV fixture copies: import 49.369 ms, repeat rescan 35.163 ms. Each record commits with synchronous FULL; seeded metadata insertion was 56.157 / 752.522 / 3882.129 ms. These are cached local filesystem measurements. Slow external volumes, long/corrupt headers, network volumes and genuine large collections need further measurement.

## Limits

Older macOS runtime testing remains outstanding. The project targets macOS 14, but this host's Homebrew Rust standard library emits pre-existing macOS 27 deployment warnings. Full Unicode case folding, fingerprints for moved files and auto filesystem monitoring are deferred. UI holds the full result list after paged transfer. Scans refresh the table on completion; progress is live. Audio callback constraints and resampling limitations remain those of v0.1.1.


## Native startup and idle measurements

Temporary off-main readiness markers were added to v0.1.1 Swift sources (linked to its saved engine archive) and to v0.2. The window marker fires from onAppear; the library marker fires after the full result list is assigned. Six fresh processes per case, first run reported separately and remaining five used for medians. Timing includes spawn/OS/SwiftUI/bridge work and measures state publication, not completion of display compositing. All readiness instrumentation was removed from final sources. The reproduction patch and driver are archived in docs/spikes/native-readiness.patch and native_startup_bench.py; baseline files come from d508375 with the same window marker. Baseline driver binary location follows the host SPM layout.

| Case | First window ms | Warm window median ms | First library ready ms | Warm library median ms |
| --- | ---: | ---: | ---: | ---: |
| v0.1.1, no DB | 723.839 | 147.070 | n/a | n/a |
| v0.2, 270 tracks | 252.188 | 179.546 | 360.187 | 238.682 |
| v0.2, 25,000 tracks | 289.138 | 177.874 | 739.676 | 469.909 |

Warm added time to fully published library: approximately 92 ms at 270 tracks or 323 ms at 25,000, relative to v0.1.1's empty window. Window readiness is independent of asynchronous indexing/database setup. These runs use cached binaries and DB pages; no controlled cache purge or genuine cold-start comparison is claimed. Turso was a link/persistence spike with no persistent native library UI, so its comparable startup evidence is the standalone DB overhead above rather than an invented full-UI timing.

Idle sample physical footprint after startup: v0.1.1 28.3 MB (peak 29.1); v0.2 270 tracks 39.3 MB (peak 39.4); v0.2 25,000 tracks 75.3 MB (peak 88.1). RSS was 102,320 / 109,424 / 137,440 KiB respectively; RSS and physical footprint are different OS accounting measures. Single ten-second CPU intervals after three seconds of settling measured 2.3% / 0.3% / 0.2% of one core (0.23 / 0.03 / 0.02 CPU seconds). These noisy short samples establish no ongoing CPU regression; they are not a claim that v0.2 improves idle CPU. Playback was stopped; no indexing or status polling remained. Sample stacks show the database worker waiting on its receiver and the main thread in the event loop.
