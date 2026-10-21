# Testing

## Standard checks

On a configured Apple Silicon development Mac, run:

```sh
./scripts/check.sh
```

This checks Rust formatting, runs Rust tests and Clippy with warnings denied, builds the release app, runs Swift tests, and validates the C header, bundle metadata and signature. The build generates the app icon and dependency notices before signing.

Rust tests cover decoding, metadata, playback state, command ordering, stale-work fencing, C ownership/buffer contracts, imports, playlists, M3U8 exchange and database recovery. They do not require an audio output device. Swift tests cover bridge lifetime, playback coordination, artwork, native table interactions, focus, accessibility and compact layouts. Tests use synthetic fixtures and temporary storage.

Some Swift tests are opt-in because they open CoreAudio streams or generate large benchmark workloads. A default skip for those tests is expected. Do not enable them against a personal library or use passing tests as evidence of audible or bit-perfect playback.

## Fixtures

Small original WAV/FLAC fixtures are checked in. To regenerate them, install ffmpeg and run:

```sh
python3 scripts/generate-fixtures.py
```

See [fixture provenance](../tests/fixtures/README.md). Keep test data synthetic and small; do not commit music, private databases or personal paths.

## Native playback integration

Generate silent playback and boundary-marker fixtures in ignored build storage:

```sh
python3 scripts/generate-audio-fixtures.py build/audio-fixtures
RESON_AUDIO_FIXTURES="$PWD/build/audio-fixtures" RESON_NATIVE_PLAYBACK_TEST=1 \
  swift test --package-path macos \
  --filter 'AudioRefinementIntegrationTests|TransitionIntegrationTests|PlaylistIntegrationTests'
```

These tests open real output streams. Audio-refinement tests use silent or muted fixtures; treat any device test as capable of producing sound. The default build must exist before Swift tests can link the Rust library. Use a controlled output and safe listening volume.

For an audible synthetic tone check:

```sh
mkdir -p build
ffmpeg -v error -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=30' \
  -ac 2 -c:a pcm_s24le build/check.wav
ffmpeg -v error -y -i build/check.wav -c:a flac build/check.flac
cargo run --release -p reson-engine --example live_check -- build/check.wav build/check.flac
```

This checks engine state with a real output and produces sound. It does not measure output precision.

## Manual review

For playback changes, try FLAC/WAV, pause/resume, seeking, Stop/restart, EOF progression, missing files and device recovery. For UI changes, check keyboard navigation, focus, long metadata, compact windows and accessibility settings. For a release, inspect the packaged app's icon in Finder, confirm it opens and verify the published checksum. Record the app commit, macOS version and output hardware in your PR.

See [performance](performance.md) for optional benchmarks.
