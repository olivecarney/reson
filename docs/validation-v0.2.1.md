# v0.2.1 validation

2026-10-13, local Apple Silicon/macOS 27.0.1. Base is merged `main` at `7087b10`; annotated `v0.2.0` was created locally at that commit with explicit user authorization. Work is on `reson-v0.2.1`; no tag/branch push, merge or publication.

## Automated checks

Final commands: cargo fmt check, all 46 Rust tests, Clippy with warnings denied, `scripts/build.sh`, Swift tests, plist lint, signature verification and C-header syntax. Swift has 29 discovered tests: 28 ordinary tests pass, and the opt-in artwork benchmark is skipped in the ordinary run and passes in its separate enabled run. The existing diagnostic bridge benchmark was also enabled separately and passed.

Test-first red runs demonstrated missing FLAC/WAV extraction, missing cache/image behavior and reuse of a larger cached thumbnail, stale presentation/cell handling, missing visible artwork refresh on rescan and the unbounded WAV description case before implementation. Further regression checks cover version 2.4, unsupported tag flags, seeking over a 100 MB sparse WAV audio chunk, cancelled requests, memory eviction, native scrolling and compact layout. Original tests for playback output notices, import cancellation, persisted IDs/reopen and process-interruption recovery remain intact.

Artwork cases include front-picture FLAC metadata, WAV APIC with single-byte/UTF-16 descriptions, absence/missing source, truncated metadata, oversized payload/dimensions and invalid image data; 80/384 thumbnails; cache creation/restart reuse/negative caching/invalidation/corruption recovery; repeated requests and terminal shutdown with a request in flight. A delayed old extraction proves rapid selection rejects stale results and transport loading is independent. Native reused cells are checked with differently shaped images. A 1,000-row AppKit test scrolls to 0/800/801/999/0, checks current image identity/shape and selection, and verifies fewer than 40 cache files are created. Rescan refreshes visible artwork without a full-table reload. The native NSHostingView layout test checks actual 820 × 520 and 1180 × 740 content frames and minimum dimensions with both panels and a long title.

The host continues to emit previously documented Rust standard-library macOS 27-versus-14 deployment warnings. Older-macOS runtime compatibility is not established by this build. No warning suppression or deployment-target workaround was added.

## Native smoke evidence

Only original synthetic audio/images under ignored `build/v0.2.1-smoke` and `RESON_LIBRARY_PATH` overrides were used. No personal music or Application Support database was accessed.

- Imported a 60-second FLAC with a green cover, a 60-second WAV with an amber APIC cover, and a WAV without artwork: three indexed, zero skipped. The table showed both covers and a native placeholder.
- FLAC play/pause/resume and WAV play/pause/resume/stop/restart worked. Stop reset position; pause held it. The playing-track transport and selected-track inspector were visually confirmed to show different covers simultaneously.
- Imported 25,000 artwork WAV hardlinks while WAV remained Playing; subsequent snapshots advanced from 0:19 to 0:25 during search. A real DeviceChanged output notice remained nonfatal. No recurrence of the old terminal playback failure occurred.
- Search by artist and filename and native title-header sorting worked. Ten five-page scrolls in the 25,003-track library showed current row images; automated scrolling additionally alternates image shapes to detect wrong reuse. Inspector scrolling exposed all metadata and file location. Native window zoom worked; minimum-size layout was additionally verified in a native host test.
- Quit and restarted the final app: all 25,003 tracks returned without reimport, with visible artwork. Disk reuse across independent cache instances is proven by tests whose extractor fails if called on a disk hit.
- Replaced the synthetic WAV cover with blue artwork, preserving its path, then used File → Rescan Folders. Both its visible table cell and selected inspector updated to blue. The saved ID/records remained present; schema was still 1.
- Final WAV play/pause/resume/stop/restart and Command-Q passed. Both native sessions exited with status 0. No Reson process remained; SQLite integrity_check returned `ok`, user_version `1`, with 25,003 tracks and two folder records.

Native import-cancel timing, physical device disconnection, audible listening/loopback, bit-perfect output, slow external volumes and whole-app leak attribution were not independently exercised here. Existing automated cancellation/reopen tests pass. Shutdown with an explicitly delayed artwork request is covered by service tests; the native quits followed artwork/audio/database activity.

## Footprint and readiness

Final executable: **2,958,448 bytes**. The merged playback-fixed v0.2 executable was 2,740,656 bytes: +217,792 bytes (+7.95%). Relative to the original milestone's 2,723,792-byte build, the increase is 8.61%. No new package dependency or database migration. SQLite remains the macOS system library.

Controlled comparison rebuilt Swift from local `v0.2.0` and the v0.2.1 source, linking the same unchanged engine. Original artwork WAV entries were selected into isolated 270/25,000-record DB copies. Temporary off-main window/onAppear and full-list publication markers exist only in ignored benchmark copies. Six fresh processes per case; first run excluded from warm medians. Readiness means state publication, not completed compositing. No cache purge or controlled cold-start claim.

| Case | Warm window ms | Warm library ms | Idle physical footprint | Peak footprint | Idle CPU, 10 s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rebuilt v0.2.0, 270 | 180.843 | 249.162 | 36 MiB | 39 MiB | 0.1% |
| v0.2.1, 270 | 170.151 | 250.719 | 38 MiB | 42 MiB | 0.0% |
| Rebuilt v0.2.0, 25,000 | 167.778 | 478.322 | 55 MiB | 69 MiB | 0.1% |
| v0.2.1, 25,000 | 166.948 | 443.911 | 55 MiB | 67 MiB | 0.0% |

Original v0.2 historical measurements were 39.3 MiB/179.546 ms/238.682 ms at 270 tracks. Different metadata, compiler/OS cache state and noisy short samples prevent attributing small apparent speedups to artwork. The same-input comparison shows approximately +2 MiB at 270 tracks and +1.6 ms to library publication, with no persistent idle CPU detected. RSS is a separate metric (v0.2.1 112,064/116,912 KiB in the final warm samples); footprint accounts for compressed memory differently.

After the native 25,000-entry import and ten rapid scroll bursts, physical footprint was 114 MiB, peak 134 MiB; RSS 171,456 KiB, instantaneous CPU 0.0% after settling. This includes import/query buffers, AppKit/accessibility inspection and prior audio activity, and is not an isolated artwork allocation measurement. After restart the controlled 25,000 case above measured 55 MiB. Artwork decoded cache limits are enforced directly, and eviction/cancellation/lazy-row tests guard against unbounded artwork growth; full metadata arrays still scale with library size as in v0.2.

## Cache workload

The opt-in Swift test uses an original 300 × 200 PNG in bounded FLAC picture metadata, with distinct source paths (hardlinks). Every source is deliberately requested sequentially, then a fresh cache instance requests every disk entry. This is a stress benchmark, not app startup behavior. Debug XCTest service timings include async dispatch, stat/keying, extraction where needed, ImageIO decode/thumbnail/PNG encode and atomic writing. Disk-hit timing includes thumbnail decoding. The app requests visible rows, not all these entries.

| Sources | Total 80px miss s | Mean miss ms | Total disk hit s | Mean hit ms | 30 inspector misses ms | Logical cache bytes | Allocated KiB (`du -sk`) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 270 | 0.227544 | 0.843 | 0.070773 | 0.262 | 30.514 | 140,160 | 1,200 |
| 5,000 | 4.095595 | 0.819 | 1.371723 | 0.274 | 33.503 | 1,729,440 | 20,120 |
| 25,000 | 20.170431 | 0.807 | 9.598995 | 0.384 | 37.277 | 8,449,440 | 100,120 |

Each case includes 30 inspector thumbnails in disk size. Real complex photographs may compress much less than this solid-color fixture. Small files have appreciable filesystem block overhead. Old identity keys remain disposable but are not automatically pruned; disk cache growth is a remaining limitation. No full-resolution blobs or SQLite artwork data are stored.

## Library performance

Unchanged `library_bench` on new isolated DBs: 270/5,000/25,000 all-page queries took 0.173/3.650/35.388 ms; first-page reopen 0.662/0.701/0.962 ms. 270 short original WAV imports took 50.925 ms (v0.2: 49.369); repeat rescan 50.292 ms (historical 35.163). Artwork is not extracted by indexing. These single runs are noisy and do not establish a scanner regression. Schema and database sizes match v0.2: 102,400/1,122,304/5,537,792 bytes. Swift bridge warm search medians were 0.112/1.300/6.282 ms.

## Reproduction and review

Run all standard commands in the milestone brief. Enable the artwork stress test with:

```
RESON_ARTWORK_BENCHMARK="$PWD/build/artwork-bench-fresh" swift test --package-path macos --filter ArtworkBenchmarkTests
cargo run --release --example library_bench -- build/library-bench-v0.2.1
RESON_BENCHMARK_DATABASES="$PWD/build/library-bench-v0.2.1" swift test --package-path macos --filter LibraryBridgeTests
```

Use a fresh artwork output path for cold cache misses. For complete app readiness comparison, prepare synthetic music and an isolated imported DB, make SQLite backup copies named `build/v0.2.1-smoke/270.db` and `25000.db` containing that many original-artwork tracks, then run `python3 scripts/benchmark-artwork-startup.py`. It compiles isolated copies, emits JSON timing/CPU rows and saves OS footprint reports. It never patches production sources. The benchmark captures main-thread publication with off-main stdout markers; image generation remains off-main.

Native diff review checked source bounds, request identity/cancellation, cache recovery/memory ownership, rescan refresh and separation from playback/SQLite. Test and measurement evidence is above; the branch is prepared for the user's pre-merge review. Unsupported WAV conventions, absent automatic disk eviction, external-file refresh rules and host runtime/profiling limits are explicitly retained. No merge, tag for v0.2.1, push or publish is authorized/performed.
