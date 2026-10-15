# v0.5 validation

This document preserves the earlier milestone checkpoints. The **Native macOS design correction** section below records the final correction and supersedes the earlier visual follow-up descriptions.

Validated on the development Apple Silicon Mac on 14–15 October 2026, starting from clean `origin/main` at merged v0.4 `3ae7eea0e1b7616bec5782f1a02f032651213a8d`. Implementation uses `reson-v0.5`. Rust audio, the C ABI, SQLite/schema 2, queue policy and artwork-cache algorithms are unchanged. Only original synthetic audio, generated metadata databases and isolated application settings/cache were used; personal music and the real application database were not used.

## Required gates and regression coverage

The required commands pass:

- `cargo fmt --all -- --check`
- `cargo test --workspace`: **75 tests passing**.
- `cargo clippy --workspace --all-targets -- -D warnings`
- `./scripts/build.sh`
- `(cd macos && swift test)`: **86 discovered, 78 passing, eight opt-in skips, zero failures**.

All eight opt-in cases also ran successfully: the explicit bridge/CoreAudio/playlist integration group passes 11 tests, the release native-interface/playlist benchmark group passes two, and the artwork workload/maintenance benchmark group passes two. Counts overlap the default discovery and must not be added as distinct tests. Ordinary playlist, artwork identity/cancellation/reuse, disk pruning, SQLite recovery, seek generation fencing, volume, output recovery and queue-history regressions remain passing.

New behavioural coverage verifies Return playback by occurrence ID, missing-row Play rejection, valid context actions and move boundaries, deselection clearing inspector identity, numeric alignment/full-text help, native disabled timeline/accessible values and Home/End bounds, sidebar/table labels and selection repair, focused-control Space routing, native table focus restoration and cancellation after another navigation, library-sort indicator restoration, and playing-indicator refresh after native column reordering. The keyboard test reproduces AppKit's stale `clickedRow` selecting the wrong occurrence after a later keyboard selection; keyboard actions now use selected rows while context menus retain clicked-row semantics. Native hosting checks cover compact 820×520, normal 1180×740 and large 1600×1000 layouts, long titles, independent selected/playing snapshots and a usable timeline width with both panels visible.

Regression-first failures exposed missing Return/Play actions, invalid boundary actions, stale inspector selection, missing alignment/tooltips, stale sort indicators, delayed navigation stealing focus and stale pointer targets overriding keyboard selection. These are resolved. A focus test initially yielded the main actor without allowing its queued AppKit focus action to execute; it now permits a bounded asynchronous wait and uses a configured native table. No failing test is accepted for merge.

The build retains the existing Rust-standard-library/macOS-27 deployment warnings. The requested minimum remains macOS 14; execution on older macOS releases is unverified. There are no new Swift package or Rust dependencies.

## Native application and visual review

The real application was built from an ignored source copy under `build/v0.5-smoke`, using a dedicated bundle identifier, settings suite, database and artwork directory. Final smoke sources embed their synthetic database path so relaunching the smoke bundle cannot select the normal library. The earlier source copies used `RESON_LIBRARY_PATH` explicitly. No generated app, audio, database or screenshot is tracked.

The baseline review inspected the empty library, first synthetic import, native table selection and artwork inspector. Refinement review found oversized artwork when resizing the initial inspector implementation; artwork is now bounded at 176 points. Compact hosting screenshots confirm the overflow actions menu, readable transport and scrolling inspector without a wider required window. Final native screenshots show dense aligned rows, full normal-width column headers and distinct green selected-track/blue playback artwork. Native zoom and fullscreen were exercised; standard, fullscreen and hosting evidence is retained only in ignored development artifacts.

The native journey exercised:

- Empty library, original Amber FLAC/Blue WAV/Short WAV import, artwork and placeholder rows, search/no results/clear and sorting.
- Selection, select-all, context menus and Return-to-play; Space pause; selected-track versus playing-track independence.
- Playlist creation, multi-track Add to Playlist, keyboard reorder, rename and deletion; deletion returns to Library without changing playback context. A final native rerun confirmed focus returns to the track table after deletion; native tests also verify cancellation after intervening navigation.
- Play Next and Add to Queue for duplicate occurrences, queue presentation with ⌘J, keyboard reorder/removal, Clear, empty state and Escape dismissal.
- FLAC/WAV playback, paused accessibility seeking, actual coordinate click-to-seek and focused arrow seeking, mute, volume controls, source/output details and explicit built-in-speaker selection while paused.
- Restart, retained library/preferences, native quit and clean shutdown. The isolated database reports integrity `ok`, no foreign-key violations and schema 2.

A real xrun notice appeared during desktop/build load without stopping playback. It is now presented as a nonfatal information notice separately from failures, and no longer offers a misleading Open File action. Explicit output selection cleared the notice. CoreAudio integration separately verifies unavailable-device failure, retained paused position/recovery, repeated output switches, seek after recovery, rapid replacement, natural EOF and queue priority/duplicates. The final integration run observed seek acknowledgements around 2.8–3.6 ms, preserving the existing control cadence and generation checks. No hardware gain setting was written.

Literal dragging remains **inconclusive**: coordinate clicks move the timeline and arrow keys commit seeks, but the computer-use drag calls completed without moving the thumb. Native NSSlider actions/keys and the existing scrub preview/cancellation tests pass; the unchanged v0.4 native tracking implementation remains in place. Pointer playlist/queue dragging is covered by native pasteboard/drop behaviour tests, rather than a newly certified manual drag journey. This automation limitation is distinct from a reproduced application regression.

Accessibility inspection confirmed native table, sidebar, queue, transport, output and timeline labels/values, native menus, disabled controls and selection state. Reduced-motion safety comes from retaining native controls and introducing no custom animations. Full VoiceOver operation, complete Tab traversal, every appearance/contrast setting, physical output unplug and older-system compatibility were not certified. Export/import, transaction-safe duplicate reordering and missing-file behaviour have automated coverage; every possible file-picker/error path was not manually repeated.

## Footprint and readiness

The packaged native executable measures **4,057,344 bytes (4.06 MB)** versus **3,879,712 bytes (3.88 MB)** built at the v0.4 baseline: +177,632 bytes, approximately **4.6%**. Generated apps, cache and development tools are excluded from this executable measurement.

The paired startup tool copies version-matching sources, isolates settings/cache, backs up the same synthetic schema-2 databases, launches each version six times and excludes the first launch. Window-ready is an application marker, not finished compositing. The final paired warm medians are:

| Tracks | v0.4 window / library ms | v0.5 window / library ms |
| ---: | ---: | ---: |
| 270 | 465.9 / 695.3 | 229.9 / 309.3 |
| 5,000 | 214.9 / 380.2 | 215.8 / 340.8 |
| 25,000 | 193.8 / 505.0 | 228.0 / 531.8 |

The 270-track baseline was affected by initial build/desktop load. Earlier runs varied substantially; these figures do **not** establish a startup speedup. The 25k case adds about 34 ms to the window marker and 27 ms to library readiness. No major large-library readiness regression was found.

Startup-run idle CPU samples ranged from 0.0–0.8%, with other development processes active. A separate quieter matched 25k check, after five seconds of settling and ten seconds of CPU-time observation, measured **0.0% for both versions**. RSS was 139,728 KiB at baseline and 125,344 KiB current in that check; earlier RSS varied strongly with VM compression and framework residency, so no memory reduction is claimed. Two interleaved `footprint` samples at 25k measured baseline **64.90 / 79.77 MB** and current **65.16 / 79.15 MB** of physical footprint. These paired observations show comparable memory consumption, rather than the apparent differences suggested by individual RSS samples.

## Native table, queue and playlist performance

The same release `InterfaceBenchmarkTests` harness was run against archived v0.4 and current views at 1180×740 with both panels visible. It scrolls among widely separated rows 30 times, excludes the first five operations, verifies cell content and reports synchronous scroll/layout/cell work. It does not measure presented frames or certify a refresh rate.

| Tracks | v0.4 scroll median / p95 ms | v0.5 scroll median / p95 ms | v0.5 queue host ms |
| ---: | ---: | ---: | ---: |
| 270 | 4.62 / 4.89 | 4.99 / 5.31 | 19.37 |
| 5,000 | 4.62 / 4.91 | 4.73 / 5.21 | 15.38 |
| 25,000 | 4.72 / 4.95 | 4.74 / 5.05 | 15.46 |

Queue hosting includes 100 pending tracks; it is not a measurement of sheet animation latency. Baseline queue hosting was about 12–16 ms. The native interaction remains responsive; no frame-presentation speedup is claimed.

This benchmark caught a temporary 12–16 ms scrolling regression that the simpler one-column table benchmark missed. Phase timing attributed almost all added cost to host layout. A native `sample` trace showed repeated SwiftUI root geometry/size-fitting work. Controlled source-copy experiments ruled out transport adaptation and fixed versus split panes; flattening the nested header `ViewThatFits` restored approximately 4.7 ms scrolling while preserving the native split view and compact menu. No custom rendering framework or speculative playback refactor was introduced.

The existing release playlist/model benchmark produced:

| Tracks | Enqueue / queue move / clear ms | Selected edit + reload ms | Main-actor heartbeat maximum ms |
| ---: | ---: | ---: | ---: |
| 270 | 0.100 / 0.144 / 0.008 | 5.02 | 2.88 |
| 5,000 | 1.44 / 2.26 / 0.137 | 49.15 | 3.06 |
| 25,000 | 8.32 / 11.93 / 0.687 | 350.01 | 3.45 |

Archived v0.4's 25k edit/reload was 427.8 ms with a 4.02 ms heartbeat maximum in its measured run. Variation and first-case setup prevent treating these differences as a guaranteed speedup. The Rust playlist benchmark's 25k query/move medians were 2.20 / 31.63 ms; that code is unchanged. Sidebar selection and edit/reload remain asynchronous; instant zero-cost navigation is not claimed. Transport updates retain the established cadence, and native table tests confirm playback-only updates do not fully reload rows or reset column configuration. There is no new idle timer, polling mechanism or animation loop.

Artwork workloads also pass at 270/5k/25k. The 25k workload measured 20.10 seconds for sequential misses, 7.95 seconds for reopened disk hits and 35 ms for 30 inspector requests; these are deliberately exhaustive workloads, not typical scrolling latency. The 25k maintenance case pruned about 208 MB from a synthetic over-limit cache, with maximum concurrent request latency around 2.1 ms. Image decoding, caching and pruning remain off the main actor.

## Reproduction and artifacts

```sh
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/build.sh
(cd macos && swift test)
python3 scripts/generate-v0.4-fixtures.py build/v0.5-audio
RESON_AUDIO_FIXTURES="$PWD/build/v0.5-audio" RESON_NATIVE_PLAYBACK_TEST=1 \
  swift test --package-path macos --filter 'AudioRefinementIntegrationTests|TransitionIntegrationTests|PlaylistIntegrationTests|EngineBridgeTests'
cargo run --release -p reson-engine --example library_bench -- build/v0.5-bench/library
cargo run --release -p reson-engine --example playlist_bench -- build/v0.5-bench/library
RESON_PLAYLIST_BENCHMARKS="$PWD/build/v0.5-bench/library" \
  swift test -c release --package-path macos --filter 'InterfaceBenchmarkTests|PlaylistBenchmarkTests'
RESON_ARTWORK_BENCHMARK="$PWD/build/v0.5-artwork-bench" RESON_MAINTENANCE_BENCHMARK=1 \
  swift test -c release --package-path macos --filter 'ArtworkBenchmarkTests|ArtworkMaintenanceTests.testMaintenanceBenchmark'
mkdir -p build/v0.5-layout
RESON_INTERFACE_EVIDENCE="$PWD/build/v0.5-layout" \
  swift test --package-path macos --filter 'InterfaceLayoutTests|InterfaceRefinementTests'
```

For paired startup, archive `3ae7eea` into `build/v0.5-baseline/src`, build its matching static Rust archive into that copy's `target/release`, then run `python3 scripts/benchmark-v0.5-startup.py build/v0.5-bench/library build/v0.5-baseline/src`. The script isolates UserDefaults as well as cache/database paths. For paired native scroll measurements, copy the current `InterfaceBenchmarkTests.swift` measurement harness into the ignored baseline source copy and run its release opt-in test against the same synthetic databases. Never substitute personal library databases.

Raw local evidence lives in ignored `build/v0.5-{rust-final,clippy-final,fmt,swift-final,build-final,native-audio-final,native-bench-final,baseline-scroll,startup-final,footprint,idle-final,artwork-bench,layout-final}.log`, `build/v0.5-scroll-layout-sample.txt`, `build/v0.5-smoke/{baseline,final,fullscreen}.png` and `build/v0.5-layout/{compact,normal,large}.png`. The final normal-window screenshot includes the header performance simplification; compact/normal/large hosting evidence supplements the earlier fullscreen capture. No screenshots, generated fixtures, applications, databases, credentials or caches are committed. No release tag, GitHub Release or visibility change is part of v0.5.

## Minimal-chrome follow-up — 15 October

The subsequent interface pass removes the duplicated wordmark, footer slogan/version, status strip and codec badge; the native title is lowercase `reson`, with version/build in About reson. Time values and their native header now have an inset and a wider minimum column. A single native Liquid Glass capsule groups playback controls on macOS 26+, with a system-material fallback for earlier systems and Reduce Transparency. The table remains flat.

The follow-up build passes. Swift discovers 87 tests: 79 pass and eight opt-in cases skip by default. The new native-hosting regression checks the Time text alignment rectangle, accounting for AppKit's field alignment insets. The release interface benchmark passes separately: 25k scrolling median/p95 4.81/5.12 ms, comparable to the preceding implementation. Native visual review confirms one title, padded Time text/header, the restrained glass group and About reson showing Version 0.5.0 (7). Playback/database code is unchanged. Raw follow-up logs are ignored `build/simple-{swift,build,interface-bench}.log`.


## Typography and glass controls — 15 October

Regular 13-point table typography, lighter headings, glass header actions and matching output controls replace the previous styling. The build and 87-test Swift suite pass (79 passed, eight opt-in skips). The release native interface benchmark passes: 25k scroll median/p95 5.74/6.52 ms, compared with 4.81/5.12 ms in the preceding pass. Glass adds a small measurable layout cost; no per-row glass or animation is used. Native review covers the wide header, compact header with inspector, and opening/cancelling the file picker from the styled plus button. Reduce Transparency branches use native bordered buttons and opaque capsule backgrounds; that system preference was not toggled during visual QA. Logs: ignored `build/clean-ui-{tests,build,bench}.log`.


## Native macOS design correction — 15 October 2026

Continued the existing `reson-v0.5` branch, preserving both later commits from `codex/simplify-interface` (`e30784c`, `45ffa32`) by fast-forward. The correction baseline is `45ffa32`; the merge base on main is `9987b79`. Work was performed by one agent. Rust playback, SQLite/schema, C ABI, queue policy and dependencies are unchanged.

### Visual findings and review

The running baseline showed a broad grey content header, a custom blue-tinted Library selection, multiple independent glass capsules for secondary actions, differing sidebar/inspector/transport materials, and equal playback-button emphasis. These were visible even though the preceding code already used authentic glass APIs and system fonts. The correction moves window actions into the native unified toolbar, replaces the custom All Tracks selection with a native source list, makes library content a semantic text background and inspector content a semantic window background, and limits additional glass to one playback group. The transport uses a native title-bar material; its output controls no longer have a separate capsule. Play/Pause, timestamps and important small metadata have clearer hierarchy.

The final rendered app was reviewed at normal size and at the actual 820-point minimum width, including populated inspectors. The content minimum is 820×520; native title-bar height makes the minimum test window taller than 520. Minimum variants change only the isolated app’s initial size and inspector visibility. Normal and minimum screenshots show readable controls and unobscured artwork. The compact header no longer consumes a second row for an overflow menu. Wide table columns remain accessible through native horizontal scrolling. Inspector metadata scrolls independently; long-title hosting tests cover truncation and layout at compact, normal and large sizes. A clipped lower source-list selection corner found in hosting screenshots was corrected by allowing enough row-container height.

Before/after evidence is retained locally in ignored `build/glass-review/`:

| Requested state | Before / after evidence | Finding |
| --- | --- | --- |
| Normal library | `before-normal.png`, `after-normal.png` | Secondary actions moved out of content; calm neutral table surface. |
| Minimum-width library | `before-minimum.png`, `after-minimum.png` | Real native app windows; toolbar fits, leading columns and inspector remain usable. |
| Playlist selected | `before-playlist.png`, `after-playlist.png` | Native source-list selection; after capture includes a persisted synthetic track. |
| Queue open | `before-queue.png`, `after-queue.png` | Native sheet, current-track context and pending table; after capture includes a queued occurrence. |
| Inspector populated | `before-inspector.png`, `after-inspector.png` | Flat readable metadata and bounded artwork; no competing large blur layer. |
| Playing transport | `before-playing.png`, `after-playing.png` | One glass playback group; primary Play/Pause, standard output controls and native timeline. |
| Native popover/menu | `before-popover.png`, `after-popover.png`, `after-menu.png` | System presentation and legible audio details/context actions. App-window captures crop portions of popovers extending beyond the parent window; their complete text was checked through accessibility. |
| Empty library | `before-empty.png`, `after-empty.png` | Real fresh isolated databases, clear import action; corrected empty seek control is disabled. |
| Accessibility appearance | `before-accessibility-empty.png`, `after-accessibility-empty.png`, `after-accessibility.png`, `after-increased-contrast.png` | Real Increase Contrast and Reduce Transparency settings were toggled, including contrast alone. Opaque playback/sidebar/transport fallbacks and system toolbar outlines remained readable. Both preferences were restored to their original off values. |

Hosting evidence in `before-layout/`, `before-extra-layout/` and `after-layout/` supplements the real app captures. Cache-display hosting snapshots do not reproduce all compositor glass effects, so material judgement used the live app. Native window-edge drag automation did not resize reliably; fresh smoke bundles with minimum initial sizes supplied the actual compact-window evidence instead. Row-wide accessibility clicks can target horizontally offscreen portions of a wide table; clicking visible text/cells and invoking AppKit’s native Scroll Left action verified the intended interactions.

Live checks exercised Return-to-play, pause/resume, mute/restoration, playlist creation and insertion through native menus, playlist/Library navigation, queue insertion/presentation/dismissal, and native audio details. Focused timeline Home reached 0:00 and Right reached 0:05 while paused. Retrying System Default retained the paused position and cleared a nonfatal xrun notice observed during desktop/build activity. This repeats the previously documented environmental xrun behaviour; no playback architecture was changed. Clean quit and isolated database integrity checks succeeded. No personal music or database was used for test writes.

### Regression and compatibility evidence

The final required gate runs are logged under `build/glass-review/premerge/` and `postmerge/`: formatting, workspace Rust tests, warnings-as-errors Clippy, the packaged native build and the full Swift suite. Rust has **75 passing tests**; Swift discovers **93 tests, 85 passing and eight opt-in skips**, with zero failures. The default skip count does not represent unrun integration coverage: the explicit CoreAudio/bridge/playlist group passes **11 tests**, the release interface/playlist group passes **two**, and the artwork workload/maintenance group passes **two**. These groups overlap default discovery.

New native tests verify selection emphasis/restoration, aligned numeric digits with proportional titles, Library source-list selection and navigation, opaque material transitions without effect accumulation, high-contrast empty/queue hosting, and the compact disabled timeline. The first three appearance tests failed against the old implementation before correction. The empty-layout regression also fails against the baseline: SwiftUI can override an embedded slider’s initial AppKit enabled state. Applying the disabled state at both layers fixes the real hosted control and its native accessibility state. Final review also reproduced a duplicate Library reload: selection notification and a table single-click action both navigated before SwiftUI refreshed the coordinator. Removing the redundant single-click action leaves selection-driven navigation; the regression now verifies exactly one navigation per click. The existing cell-reuse test was updated to expect aligned digits specifically for numeric columns; it still verifies reuse, reset content, colours and stable constraints.

The installed SDK explicitly declares `glassEffect`/`GlassEffectContainer` availability from macOS 26. The package and app minimum remain macOS 14. Tested execution was on Apple Silicon macOS **27.0.1 (26A434)** with the macOS 27 SDK. macOS 14, 15 and 26 execution was **not** performed. Availability guards and native fallbacks compile, but that is not a claim of runtime certification on those releases. Existing Rust standard-library deployment-version linker warnings and the existing test weak-reference warning remain. Full VoiceOver operation, exhaustive Tab traversal and physical output unplug remain unverified. Native drag/drop, selection repair, queue identity, seek fencing and clean shutdown retain their behavioural test coverage; literal pointer-drag certification remains limited by automation.

An early comparison-copy integration invocation lacked the relative fixture directory and observed the default output device changing during a switch loop. Its failures are retained in `before-audio.log`; the correctly configured current-repository integration run passes all 11 tests and retains hardware volume. The optional artwork run initially exhausted free disk space during maintenance-test setup; only this review’s generated compiler caches were removed before retrying. No product failure was accepted as a passing gate.

### Performance comparison

Both variants use the same static engine archive, synthetic schema-2 data and release flags. The uninstrumented native executable measures **4,197,432 bytes before** and **4,089,664 bytes after**: 107,768 bytes smaller (about **2.6%**). These are executables, not app/cache/build-directory sizes.

The first 270/5k/25k startup sweep varied during native QA and accessibility-setting activity. A quieter six-run, alternating-order 25k repeat excludes each first launch and gives:

| Metric | Before | After |
| --- | ---: | ---: |
| Warm window-ready median | 313.42 ms | 301.99 ms |
| Warm library-ready median | 636.59 ms | 626.02 ms |
| Idle CPU, 10-second observation after 5-second settle | 0.1% | 0.0% |
| RSS in that idle observation | 103,472 KiB | 100,512 KiB |

The overlapping startup ranges and variable RSS support comparable readiness/memory, not a claimed startup or memory improvement. Readiness markers are not finished compositing. The raw broad sweep and quieter repeat remain in `startup.log` and `quiet-performance.log`.

The same release native-window/queue benchmark gives:

| Tracks | Before scroll median / p95 | After scroll median / p95 | Before / after queue hosting |
| ---: | ---: | ---: | ---: |
| 270 | 6.65 / 7.02 ms | 3.28 / 3.51 ms | 23.95 / 25.35 ms |
| 5,000 | 7.31 / 10.27 ms | 3.27 / 3.48 ms | 19.29 / 18.36 ms |
| 25,000 | 6.47 / 7.09 ms | 3.28 / 3.54 ms | 17.87 / 18.31 ms |

This measures synchronous scrolling/layout/cell work, not presented frames. Moving the header’s independent glass effects out of the content layout reduces measured work; no frame-rate certification is claimed. Queue hosting remains comparable. The playlist benchmark also passes. No new animation, polling loop, shader, rendering infrastructure or dependency was introduced.

Raw evidence: `appearance-red.log`, `navigation-once-{red,green}.log`, `before-extra-layout.log` (intentional baseline regression), `swift-final.log`, `native-audio.log`, `scroll-{before,after}.log`, `artwork-bench*.log`, `startup.log`, `quiet-performance.log`, and the final gate directories under `build/glass-review/`. Packaged smoke apps and screenshots remain ignored development artifacts; source tests and these documents are tracked. No release tag, GitHub Release, repository-visibility change or branch deletion is part of this correction.
