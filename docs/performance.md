# Measuring performance

Use a release build and record the commit, Rust/Swift versions, macOS version, hardware, power mode and output device. Keep files and device configuration fixed. Report sample counts, individual measurements, median/range and tool overhead. Separate warm launches from first-after-reboot launches.

## Profiling the app

- Measure process launch to an interactive window with Instruments App Launch/System Trace. Quit normally between trials.
- For idle CPU and memory, settle for 60 seconds and sample for another 60 seconds. Report physical footprint or RSS rather than virtual address space.
- Measure playing, paused and stopped states separately. Pause retains a stream; Stop releases it. Use a checksummed file long enough to cover the measurement interval.
- For imports, report file count, format/tag/artwork characteristics, cache state, elapsed time and the amount of completed work. A metadata-only benchmark does not measure real audio-file scanning.

Do not infer audio continuity from UI timings or zero CPU from a rounded process reading. Listening/loopback capture is required to assess glitches and boundary continuity.

## Synthetic workloads

Create isolated metadata databases and run library/playlist benchmarks:

```sh
cargo run --release -p reson-engine --example library_bench -- build/library-bench
cargo run --release -p reson-engine --example playlist_bench -- build/library-bench
RESON_PLAYLIST_BENCHMARKS="$PWD/build/library-bench" \
  swift test --package-path macos --filter 'PlaylistBenchmarkTests|InterfaceBenchmarkTests'
```

These use 270, 5,000 and 25,000 synthetic metadata records. They test model/table work, not decoder throughput or real music indexing.

Optional artwork workloads:

```sh
RESON_ARTWORK_BENCHMARK="$PWD/build/artwork-bench" \
  swift test --package-path macos --filter ArtworkBenchmarkTests
RESON_MAINTENANCE_BENCHMARK=1 \
  swift test --package-path macos --filter ArtworkMaintenanceTests.testMaintenanceBenchmark
```

For muted playback transition timing, generate the [audio fixtures](testing.md) and run:

```sh
cargo run --release -p reson-engine --example audio_bench -- build/audio-fixtures
```

Use dedicated build directories; benchmark output and generated databases are not source assets.
