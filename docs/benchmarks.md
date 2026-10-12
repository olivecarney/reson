# Reproducible performance baseline

Use the release packaged app, not cargo run or Swift's debug build. Record commit, Rust/Swift versions, OS/build, hardware, power mode, display configuration, output device, output stream format and test-file checksum. Keep the device and files fixed; close unrelated CPU-heavy applications. Avoid confusing startup results on a warm filesystem with cold-cache startup.

## Startup

Measure ten launches from process creation to the first interactive window. Use Instruments App Launch/System Trace with a consistent observation of window availability. Separate first-after-reboot trials from warm restarts; ten warm launches are not ten cold launches. Record every duration plus median/range and whether profiling overhead is included. Quit normally between trials. Do not add continuous runtime instrumentation solely for the benchmark.

## Idle

Launch without opening a file, settle for 60 seconds, then record CPU and physical memory for 60 seconds using Instruments Activity Monitor or a consistent process sampler. Repeat three times. Record startup peak separately from settled memory. Report physical footprint/RSS precisely; virtual address space is not RAM usage.

A basic process sampler, less precise than Instruments:

```sh
reson_pid=$(pgrep -x Reson)
ps -p "$reson_pid" -o pid,%cpu,rss,time
```

CPU from ps may be a lifetime average. Use interval-based Instruments data for steady-state conclusions. Do not infer zero CPU from one rounded reading.

## Playback and pause

Use a checksummed local 60+ second WAV/FLAC, a fixed device and documented source/output rates. Settle 10 seconds, sample 60 seconds of playback, repeat three times. Repeat for paused playback because the output stream is retained; stopped playback should release it. Observe glitches separately from CPU averages. Measure with and without Instruments to estimate tool overhead when relevant.

## Indexing

Deferred with Phase 2. Once indexing exists, benchmark the 270-track collection and a larger fixed collection, reporting cold/warm cache separately, file count/size/tag/artwork characteristics and elapsed indexing time.

No startup, RAM or CPU results have been claimed for v0.1. This document is the baseline protocol, not completed profiling. Optimization should follow measured findings.
