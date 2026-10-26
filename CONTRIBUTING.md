# Contributing to reson

Contributions to playback reliability, library organisation, accessibility, documentation and tests are welcome. For larger features, open an issue first so we can agree on the problem and direction.

## Set up

Use an Apple Silicon Mac, Xcode 26+ with the macOS 26 SDK and Swift 6.2+, Rust 1.99.0 or newer with the `aarch64-apple-darwin` target, and Python 3.10+. CI pins Rust 1.99.0. ffmpeg is needed only to regenerate audio fixtures.

Fork and clone the repository, create a focused branch, then run:

```sh
./scripts/build.sh
./scripts/run.sh
```

The app targets macOS 14+. Release builds use the official Rust toolchain; a locally packaged standard library can impose a newer runtime requirement. Testing on older macOS releases is valuable.

Read the [architecture](docs/architecture.md) before changing worker ownership, the C bridge or persistence. The [user guide](docs/user-guide.md) and [audio behaviour](docs/audio.md) describe expected behaviour and known limitations.

## Make a change

Follow the existing Rust and Swift patterns. Keep filesystem, database and playback setup work off the UI thread. Preserve the C header's ownership, buffer and threading contracts. Prefer focused changes that are easy to review.

Add regression tests for changed behaviour. Tests should exercise a user-visible result or a meaningful contract, rather than duplicate implementation details. Keep unrelated refactors separate. Update the relevant guide when behaviour or setup changes.

The app icon source is `macos/Resources/AppIcon.icon/Assets/AppIcon.png`, a transparent PNG. Keep the area outside the dark tile transparent, with no white matte or border. The enclosing `AppIcon.icon` can be opened in Xcode's Icon Composer. Replace the PNG to change the artwork; the build generates the macOS icon representations. Do not edit generated files in `build/`.

## Check and submit

Run `./scripts/check.sh` before opening a pull request. See [testing](docs/testing.md) for optional native playback checks and [performance](docs/performance.md) for benchmarks. Test playback or UI changes manually as well, and include the macOS version, hardware, steps and results. Add screenshots for UI changes.

GitHub runs a single build/test/package pipeline per push or pull-request update, with Rust caches. Pull requests only upload build artifacts. A successful `main` build publishes the same verified DMG when the app version is new; version bumps are release decisions and belong in maintainer-reviewed changes. See the [release guide](docs/releases.md).

Describe the problem, the resulting behaviour and any limitations in your PR. Link the related issue. Maintainers review contributions; passing CI does not automatically merge or publish them.

Do not commit personal music, album artwork, library databases, private file paths, signing credentials or generated build output. Use the [synthetic fixtures](tests/fixtures/README.md) for reproducible tests.

## Community and licensing

Be respectful and constructive; follow the [code of conduct](CODE_OF_CONDUCT.md). Report reproducible bugs through GitHub issues with expected/actual behaviour and environment details. Report vulnerabilities privately through the [security policy](SECURITY.md).

Contributions to original project code and artwork are licensed under [MIT](LICENSE). Dependencies retain their own licenses. Maintainers can find packaging and publication steps in the [release guide](docs/releases.md).
