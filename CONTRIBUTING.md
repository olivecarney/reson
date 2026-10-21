# Contributing to Reson

Reson is a native macOS player for local lossless music. Contributions to playback reliability, library organisation, accessibility, documentation and tests are welcome.

## Get started

1. Read the [README](README.md) for supported formats, architecture and limitations.
2. Use an Apple Silicon Mac, Xcode 26 or newer (macOS 26 SDK and Swift 6.2+), Python 3, and a current stable Rust toolchain with the `aarch64-apple-darwin` target. The app targets macOS 14+; testing on older supported systems is valuable.
3. Fork and clone the repo, then run `./scripts/build.sh` and `./scripts/run.sh`.
4. Make a focused branch. Open an issue before a large feature or architecture change so we can agree on direction.
5. Run `./scripts/check.sh` before submitting a pull request. This builds the Rust library before Swift tests that link it. Device playback and benchmarks are opt-in; see the README.

Rust tests do not require an audio device. Swift tests skip opt-in device and benchmark checks unless enabled explicitly. Test playback manually with your own FLAC/WAV files when changing playback or UI behaviour; describe the hardware, macOS version and checks in your PR. Never commit personal tracks, artwork, databases, signing keys or private library paths. Synthetic fixtures and their provenance are in `tests/fixtures/README.md`.

## Code and review

Keep Rust playback and library work off the UI thread. Preserve the C bridge's ownership, buffer and threading contracts. Follow existing Rust formatting and Swift patterns. Add regression tests for behaviour changes, document user-visible changes, and include screenshots for UI changes. Small, reviewable PRs help us move faster.

The maintainers review contributions; passing CI does not automatically merge or publish them. Report bugs with reproducible steps, expected/actual behaviour and environment details. Be respectful, constructive and welcoming; see the [code of conduct](CODE_OF_CONDUCT.md).

Contributions to original project code are licensed under the [MIT license](LICENSE). Dependencies keep their own licenses. See [release instructions](docs/releases.md) for maintainer packaging and publication.
