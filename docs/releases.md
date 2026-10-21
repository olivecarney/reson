# Releases

## One build, tested once

`.github/workflows/ci.yml` is the only build/release workflow. It runs on pull requests, pushes to `main`, and manual dispatch. Documentation-only Markdown changes skip the workflow; changes to app source, scripts, licenses or the workflow still run it. Superseded runs for the same branch are cancelled.

1. An Apple Silicon macOS 26 job installs Rust 1.99.0 and restores cached Cargo dependencies and compiled targets.
2. `./scripts/check.sh` runs formatting, Rust tests/Clippy, the release app build, Swift tests and bundle validation.
3. `./scripts/package.sh` packages that app into a DMG, verifies the image, mounts it read-only and checks the app signature, icon, version, Finder layout and Applications shortcut. It writes a SHA-256 checksum.
4. The DMG and checksum are uploaded as a 14-day Actions artifact.
5. For `main` only, a lightweight Ubuntu job downloads those exact files from the same workflow run, verifies the checksum and publishes a new version. It does not compile or package anything.

Pull requests cannot publish releases. The build job has read-only repository permissions; only the trusted publishing job has permission to write a release. Pinned action revisions and hash-checked packaging dependencies keep the tooling explicit. Rust cache keys include the architecture, toolchain and dependency lockfile; packaging downloads have their own cache.

## Publish a version

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `macos/Info.plist`. Use a stable three-part version such as `0.5.2`. The Rust engine crate has an independent version.
2. Update `docs/release-notes.md` and affected user/contributor documentation.
3. Run `./scripts/check.sh`, then `./scripts/package.sh`. Open the DMG and check the drag-to-Applications installation and icon. The first packaging run downloads tools into `build/packaging-venv`; Python 3.10+ is required.
4. Review and merge the change into `main`. A successful pipeline automatically creates the matching tag (for example `v0.5.2`) at the tested commit and publishes the DMG and checksum. Do not push a separate release tag or start a second build.
5. Download the published DMG, verify its checksum and test installation on a clean Mac where possible.

An already published version is left unchanged, so documentation-only pushes can retain the app version. To ship different app contents, bump the version. An existing tag pointing to a different commit fails publication rather than moving the tag. Existing drafts require maintainer review before retrying. Development versions in PRs are never published until merged.

For a failed publish job, rerun that job while its build artifact is still available; it reuses the verified DMG. If the build failed or the artifact expired, rerun the whole pipeline. Manual dispatch on `main` also supports recovery. Never move a published tag or replace its downloads; fix a broken release with a new version.

## Local packaging

```sh
./scripts/build.sh
./scripts/package.sh
```

The output is `build/dist/Reson-<version>-macos-arm64.dmg` and its `.sha256` file. `scripts/dmg-settings.py` defines the icon layout and Applications shortcut without automating Finder. `scripts/dmg-background.swift` renders the neutral installer background and instruction text with native typography. The packaging environment uses pinned packages and hashes from `scripts/requirements-packaging.txt`; they are build-time dependencies, not app dependencies.

`RESON_RELEASE_TAG=v0.5.2 ./scripts/package.sh` optionally checks tag/version agreement before packaging. Verification failures stop before promoting the new image to `build/dist/`.

## Signing and compatibility

The app is ad-hoc signed and is not Apple-notarized. A DMG improves installation but does not change that trust status. Gatekeeper can require explicit approval; the [first-launch instructions](../README.md#first-launch-approval) cover Open Anyway and the app-scoped `xattr` alternative for verified downloads. Developer ID signing and notarization require a maintainer-owned Apple Developer account and protected credentials. Never commit signing keys.

The app targets macOS 14+, while compilation requires the macOS 26 SDK. Official Rust release toolchains avoid the development machine's Homebrew standard-library macOS 27 linkage requirement. Testing on older macOS versions is still needed before claiming compatibility across the entire range.
