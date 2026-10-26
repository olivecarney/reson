# Testing

## Standard checks

On a configured Apple Silicon development Mac, run:

```sh
./scripts/check.sh
```

This runs release-script regression checks, checks Rust formatting, runs Rust tests and Clippy with warnings denied, builds the release app, runs Swift tests, and validates the C header, bundle metadata and signature. The build generates the app icon and dependency notices before signing.

Rust tests cover decoding, metadata, playback state, command ordering, stale-work fencing, C ownership/buffer contracts, imports, playlists, M3U8 exchange and database recovery. They do not require an audio output device. Swift tests cover bridge lifetime, playback coordination, artwork, native table interactions, focus, accessibility and compact layouts. Tests use synthetic fixtures and temporary storage.

The release-script tests use an isolated fake GitHub CLI and synthetic payloads to check first publication, existing releases, tag immutability, API errors and corrupted checksums. Homebrew sync tests also reject corrupt downloads, mismatched GitHub asset digests, draft/prerelease tags, missing assets, invalid versions and downgrades, and check idempotent mirrored-cask updates. They never contact GitHub or publish anything.

Some Swift tests are opt-in because they open CoreAudio streams or generate large benchmark workloads. A default skip for those tests is expected. Do not enable them against a personal library or use passing tests as evidence of audible or bit-perfect playback.

## Storage isolation

XCTest automatically uses a unique temporary root for default databases, WAL/SHM, artwork and file-backed preferences, even if a test omits explicit injection. Debug executables and `scripts/run.sh` use separate development storage and identity. No tests should launch the production bundle.

For an isolated release smoke build, copy the app into temporary storage, give its Info.plist the bundle ID `dev.reson.player.smoke`, re-sign it ad-hoc, then launch with `open -n <temporary-app> --env RESON_DATA_ROOT=<absolute-temporary-root>`. This identity refuses to launch without an explicit root. `RESON_DATA_ROOT` isolates all app-owned storage together; `RESON_ISOLATED=1` without a root, invalid paths, escaping storage links and the old database-only `RESON_LIBRARY_PATH` override fail closed. Native window/table preferences use the distinct smoke bundle domain. Never reset the personal library to prepare a test.

## Fixtures

Small original WAV/FLAC/MP3 fixtures are checked in. To regenerate them, install ffmpeg and run:

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
  --filter 'AudioRefinementIntegrationTests|TransitionIntegrationTests|PlaylistIntegrationTests|LibraryManagementTests'
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

For playback changes, try FLAC/WAV/MP3, pause/resume, seeking, Stop/restart, EOF progression, missing files and device recovery. For UI changes, check keyboard navigation, focus, long metadata, compact windows and accessibility settings. For a release, run `./scripts/package.sh`, inspect the DMG's Finder layout and icon, drag the app to an isolated test location, confirm it opens and verify the published checksum. Packaging already verifies the mounted app's signature and Applications shortcut. Check the icon on both light and dark backgrounds; the surround must be transparent. Record the app commit, macOS version and output hardware in your PR.

See [performance](performance.md) for optional benchmarks.
