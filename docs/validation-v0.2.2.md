# v0.2.2 artwork cache maintenance validation

2026-10-13, Apple Silicon/macOS 27.0.1. Base: freshly fetched `main`/`origin/main` at `9a6d82dc28fc00a997750fca8085b8f26ecdd225`, containing the v0.2.1 merge. Working tree was clean before creating `reson-v0.2.2`. Local commits only; no push, merge, tag or publication.

## Policy and scheduling

The default artwork directory remains `~/Library/Caches/Reson/Artwork/`. Recognized regular files count by logical size (`st_size`). A completed scan above **256 MiB** removes oldest entries until the snapshot reaches **192 MiB or less**, allowing whole-file undershoot. Modification seconds/nanoseconds determine age, with the complete filename as the deterministic tie-breaker. Both 64-lowercase-hex `-80.png`/`-384.png` thumbnails and `.none` absence markers participate. Memory limits remain **128 entries and 8 MiB decoded pixels**.

Initialization does no maintenance I/O. Automatic admission follows a completed thumbnail request, and only on a request at least five seconds after the first completed request in that cache instance. This avoids initial window/library activity without scheduling a timer. Later browsing requests admit overdue maintenance, including after 24 hours in a long-running process. A completely idle process does no maintenance. Internal `maintain(force: true)` bypasses both opportunistic admission and the daily throttle for tests/development; explicit `maintain()` bypasses the initial admission delay but respects the throttle.

The last completed check is stored in `.maintenance-v1`. It is read once per instance and atomically replaced at completion; later checks consult only memory until due. Missing/inaccessible roots suppress attempts for 24 hours in the current instance, without recording a completed scan on disk. Interrupted/failed scans publish no completion marker and suppress routine retries for 24 hours in the current instance. Marker persistence failure is nonfatal, with the in-process throttle still applied. Concurrent explicit callers join an admitted operation.

All work uses the existing utility queue. Each enumeration/deletion slice handles at most 64 entries and checks a 2 ms elapsed budget between entries, then requeues itself behind pending requests. An incremental oldest-first heap avoids a single full-directory sort. Heap entries contain filenames/stat metadata, never images. No additional queue, timer, daemon, dependency, database change or playback change was added.

## Filesystem protections

Maintenance opens every path component using directory descriptors and `O_NOFOLLOW`, rejecting symlinked ancestors and leaves. macOS's fixed `/var` and `/tmp` system aliases are spelled `/private/var` and `/private/tmp` before this walk (Foundation otherwise hides `/private` in temporary URLs). No arbitrary symlink is followed. Directory enumeration is nonrecursive through `fdopendir`/`readdir`; only exact recognized filenames and regular files passing `fstatat(..., AT_SYMLINK_NOFOLLOW)` become candidates.

Deletion is `unlinkat` relative to the pinned cache descriptor. Before deletion the regular-file type, device/inode, size and nanosecond modification/change times must still match the enumerated candidate. Files changed/published after admission are protected by change time. Writes and maintenance serialize on the same queue, and existing atomic PNG/absence writes remain intact; temporary/unrecognized names never qualify. Relative descriptor operations cannot escape into a symlink target or follow a replaced cache path. The small marker uses bounded, nonblocking, no-follow reading and an exclusive temporary file followed by descriptor-relative atomic rename.

Unexpected entries, directories, symbolic links and unrelated files are preserved. Deletion/read/marker errors are nonfatal. Disk eviction does not remove memory entries or displayed images. Later memory misses/restarts regenerate thumbnails and absence markers normally; source identity, corruption recovery and larger-thumbnail reuse are unchanged.

## Automated checks

All required commands passed:

```
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/build.sh
(cd macos && swift test)
```

Rust: 46 tests pass. Swift: 41 discovered tests, 39 pass and two opt-in artwork benchmarks skip in the ordinary run. The new maintenance benchmark also passes when enabled. Native release build succeeds. Existing macOS 27-versus-14 Rust standard-library deployment warnings remain; this host does not establish older-macOS runtime compatibility.

Test-first red compilation demonstrated the absent maintenance API/limit injection before implementation. A subsequent behavioral red run proved symlinked-parent redirection deleted the test victim; descriptor walking fixed that regression. Startup admission coverage was written before adding its delay. Temporary directories, synthetic images/audio and sparse files exercise:

- Below/exactly at ceiling, above the real 256 MiB ceiling, whole-entry target undershoot, oldest-first and identical-timestamp filename ordering.
- Positive/negative eviction and regeneration, preserved displayed/memory images, unchanged 128-entry and 8 MiB decoded limits.
- New thumbnails atomically published, a replaced candidate and a newly created marker held open for writing during a 5,000-entry scan; active queue requests, cancellation, terminal shutdown and explicit maintenance callers completing without deadlock.
- Unexpected names, directories, entry/ancestor/root symlinks, marker symlink protection, missing roots, nondirectory roots and real permission-denied deletion/marker failures.
- Daily boundary, persistent throttle across instances, force bypass and initial-thumbnail admission deferral.

Existing extraction, source invalidation, corrupt disk recovery, lazy/reused native rows, independent presentation, library import/search/sort/rescan/reopen, cancellation and playback regression tests remain passing.

## Maintenance performance

Opt-in Debug XCTest on fresh synthetic directories. Entries are sparse 16 KiB recognized files, plus a real primed thumbnail. The measured forced run interleaves 100 memory hits and 50 fresh synthetic FLAC extraction/encoding/atomic-write misses. Enumeration includes candidate stat/heap insertion CPU time, excluding queue waits; total includes queue waits, deletion and marker publication. Before/after are the enumeration snapshot adjusted for successful deletions, not a second directory scan; newly published protected thumbnails may be included depending on enumeration timing.

| Entries | Enumeration ms | Total ms | Before bytes | After bytes | Removed bytes | Memory hit p95 / max ms | Miss p95 / max ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 270 | 1.000 | 2.989 | 4,424,688 | 4,424,688 | 0 | 0.078 / 1.122 | 0.918 / 0.998 |
| 5,000 | 21.277 | 47.172 | 81,923,696 | 81,923,696 | 0 | 0.355 / 1.226 | 1.250 / 1.414 |
| 25,000 | 112.847 | 746.119 | 409,615,120 | 201,324,992 | 208,290,128 | 0.400 / 1.365 | 1.450 / 2.701 |

An earlier memory-hit-only run took 1.577/29.382/1,098.833 ms total, with the largest sampled request at 3.189 ms. Filesystem/compiler/cache contention and deletion variability matter; maintenance is neither free nor guaranteed nonblocking. Batch yields kept measured ordinary requests responsive on this host.

Reproduce with:

```
RESON_MAINTENANCE_BENCHMARK=1 swift test --package-path macos --filter ArtworkMaintenanceTests/testMaintenanceBenchmark
swift test --package-path macos --filter ArtworkMaintenanceTests
```

## Startup and idle CPU

Ignored copies of merged v0.2.1 and current sources were built in release mode with the same unchanged Rust library. Only the copies received off-main `RESON_WINDOW_READY`/`RESON_LIBRARY_READY` logging as in `scripts/benchmark-artwork-startup.py` and `ArtworkCache.shared` directory injection. SQLite backups of the prior synthetic 270/25,000-track fixtures were used. Each process received a separate cache preseeded with approximately 300 MiB of sparse recognized files, so a full cache could not hide startup work. Six processes per case; first excluded from warm medians. No cache purge or cold-start claim; readiness measures state publication, not completed compositing.

An initial implementation admitted scans after initial visible thumbnails: warm 25,000-track library publication was 539 ms versus 450 ms baseline, and the 270 case was noisy (262 versus 226 ms). This prompted the five-second, subsequent-request admission rule. Final repeat:

| Build | Tracks | Warm window ms | Warm library ms | Idle CPU over 10 s |
| --- | ---: | ---: | ---: | ---: |
| v0.2.1 | 270 | 183.556 | 262.126 | 0.2% |
| v0.2.2 | 270 | 170.382 | 230.029 | 0.0% |
| v0.2.1 | 25,000 | 161.490 | 453.302 | 0.0% |
| v0.2.2 | 25,000 | 161.136 | 428.434 | 0.0% |

Small apparent improvements are measurement noise, not a claimed speedup. No initial scan is admitted by the final design and no readiness regression or persistent idle CPU was detected. Reproduction recipe: follow the existing readiness script, substitute `main` for its `v0.2.0` baseline, copy current sources as the other case, back up the synthetic fixture databases into a new output directory, inject separate test cache directories into both copied `ArtworkCache.shared` initializers, preseed them using sparse files, then run the same six-process measurement loop. Local exact runner/logs remain in ignored `build/benchmark-v022-startup.py` and `/tmp/reson-v022-startup-final.log`.

## Native smoke

A separately identified ignored app copy used current release Swift sources with only readiness logging and injected cache directory, plus a fresh `RESON_LIBRARY_PATH` database. Synthetic 60-second artwork FLAC/WAV and artwork-free WAV copies under `build/v0.2.2-smoke/music` were imported: three indexed, zero skipped. No personal music was selected or scanned.

Native table covers/placeholders displayed correctly. FLAC play/pause/resume and WAV play/pause/resume/stop worked; elapsed playback advanced while searching, sorting and rescanning. Selecting the blue WAV while the green FLAC played showed different inspector and transport covers simultaneously. Command-Q exited with status 0. Reopening restored all three tracks and covers without import; one removed table thumbnail and one removed absence marker were recreated. Remaining entries persisted (disk reuse without extraction is separately proven by service tests). Final Command-Q again exited with status 0; no smoke process remained. SQLite integrity was `ok`, schema version 1, with three records.

## Limits and review readiness

This is opportunistic bounding, not an instantaneous quota: a burst can exceed the ceiling until an eligible request, and continued writes/protected entries/deletion failures can leave usage above target. A completely idle app waits until further artwork activity; reopening also requires a later eligible request. Logical bytes exclude filesystem block overhead, unrelated entries and the small maintenance marker. Snapshot totals are approximate during concurrent publication. Transient candidate metadata grows with directory entry count; decoded image limits are unchanged.

One filesystem call can exceed the 2 ms slice budget or stall shutdown. A same-user external writer can still race the narrow recheck-to-unlink interval; unlink never follows its replacement link or recursively removes a directory, but this is not a transactional directory snapshot. No multi-process maintenance lock or persistent LRU is introduced. Backward wall-clock changes delay routine admission until the stored date catches up; force remains available. Physical output-device disconnection, audible/bit-perfect verification, slow external filesystems and older macOS runtime behavior were not newly tested.

The branch is ready for review and merging based on automated/native evidence above; merge/push/tag/release require separate user authorization.
