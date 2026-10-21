# Releases

Pull requests and pushes to `main` run `.github/workflows/ci.yml` on an Apple Silicon macOS 26 runner. It checks formatting, Rust tests and Clippy, builds and signs the app, runs Swift tests and validates the bundle, then uploads a zip and SHA-256 checksum as a 14-day Actions artifact. For a durable download use GitHub Releases.

## Publish a release

1. Merge and validate the intended source on `main`.
2. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `macos/Info.plist`. The Rust engine crate has an independent version.
3. Update `docs/release-notes.md` and the README for user-visible changes and known limitations.
4. Run `./scripts/check.sh`, then `./scripts/package.sh`. Inspect the archive and try a local install. CI uses the official stable Rust toolchain; Homebrew toolchains may impose a newer macOS runtime requirement.
5. Commit and push the changes, then create and push an annotated tag matching the app version, for example `git tag -a v0.5.0 -m 'Reson 0.5.0'` and `git push origin v0.5.0`.
6. The release workflow repeats the checks and publishes the archive and checksum with installation notes and generated changes. Verify the downloadable app on a clean Mac where possible.

`RESON_RELEASE_TAG=v0.5.0 ./scripts/package.sh` checks tag/version agreement before packaging. A mismatch fails publication. Failed workflows publish no release; fix the failure before retrying. Do not move an already published tag; ship a new version. To withdraw a broken release, mark it as a prerelease or remove it and communicate the reason.

## Signing and compatibility

Builds are signed ad-hoc and are not notarized. Gatekeeper may require explicit approval as described in the README. Developer ID signing and notarization require a maintainer-owned Apple Developer account and protected credentials and are future work. Never commit signing credentials.

The app targets macOS 14+, but the SwiftUI source requires a macOS 26 SDK to compile. Release builds use GitHub's official Rust installation rather than the local Homebrew standard library built for macOS 27. Testing on macOS 14–26 is still needed before claiming compatibility across that range.
