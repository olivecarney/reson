# Reson

<img src="macos/Resources/AppIcon.icon/Assets/AppIcon.png" width="96" alt="Reson app icon">

A lightweight native macOS player for local music. Rust handles playback; SwiftUI and AppKit provide the interface. No accounts, telemetry or cloud services.

## Download

**[Download the latest release](https://github.com/olivecarney/reson/releases/latest)** for Apple Silicon. Open the `macos-arm64.dmg`, drag **Reson** to **Applications**, then eject the disk image and open Reson from Applications.

The app targets macOS 14 or newer. Compatibility across older macOS versions is still being tested; Intel Macs are not supported.

The DMG includes a drag-to-Applications layout and a SHA-256 checksum.

### First-launch approval

Reson is ad-hoc signed, but not Developer ID signed or Apple-notarized. If macOS blocks it, attempt to open it, then choose **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/en-gb/102445).

After [verifying the release checksum](docs/release-notes.md#download-and-install) and copying Reson to Applications, you can alternatively remove the download quarantine for this app in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Reson.app"
open "/Applications/Reson.app"
```

Use this only for a release you trust. The command targets the installed Reson bundle; it does not disable Gatekeeper globally. If you installed elsewhere, substitute that app path. For a permissions error, use Open Anyway instead.

### Homebrew

```sh
brew install --cask olivecarney/tap/reson
```

The [project tap](https://github.com/olivecarney/homebrew-tap) pins a verified release DMG and checksum. Uninstall preserves personal library data. The cask does not bypass macOS security approval.

Version 0.5.3 includes MP3 playback, native Settings and library management.

## Listen

- Press **⌘O** to open and play a FLAC, PCM WAV or MP3 file.
- Press **⇧⌘O** to import a music folder into your library.
- Double-click a track or press **Return** to play it. Use **Space** to pause or resume.
- Open **Settings…** with **⌘,** to manage folders and restore excluded tracks. Use **Remove from Library…** in a track’s context menu to remove records while keeping music files.
- Create playlists with **⌘N**, or use **Play Next** and **Add to Queue** from a track's context menu.

Reson supports searching and sorting your library, embedded artwork, seeking, app volume and mute, output-device selection, persistent playlists, and M3U8 import/export. Your music stays in its original folders.

See the [user guide](docs/user-guide.md) for controls, library storage and troubleshooting. Playback is not guaranteed to be bit-perfect or gapless; see [audio behaviour](docs/audio.md).

## Build from source

You need an Apple Silicon Mac, Xcode 26 or newer with the macOS 26 SDK and Swift 6.2+, current stable Rust with the `aarch64-apple-darwin` target, and Python 3.10+. CI uses Rust 1.99.0.

```sh
git clone https://github.com/olivecarney/reson.git
cd reson
./scripts/build.sh
./scripts/run.sh
```

The distributable app is built at `build/Reson.app`. By default, `run.sh` launches a separately identified **Reson Development.app** using `~/Library/Application Support/Reson Development` for its database, artwork and preferences. Rebuild after source changes; the script builds only if the release app is missing. Use `./scripts/run.sh --personal` only when you intend to open the normal app with your personal library. The first build downloads Rust dependencies. After caching them, use `CARGO_NET_OFFLINE=true ./scripts/build.sh` to build offline.

To create a verified DMG from the existing build, run `./scripts/package.sh`. Packaging installs pinned, hash-checked build tools into an isolated environment under `build/`; these are not part of the app.

## Contribute

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports, accessibility improvements, testing on older macOS versions and focused features are welcome.

- [Architecture](docs/architecture.md): components, threading and data ownership.
- [Testing](docs/testing.md): automated checks and optional playback tests.
- [Performance](docs/performance.md): repeatable measurements and benchmarks.
- [Releases](docs/releases.md): packaging, versioning and publication.

Please follow the [code of conduct](CODE_OF_CONDUCT.md). Report vulnerabilities through the [security policy](SECURITY.md).

## License

Original Reson code and app artwork are available under the [MIT license](LICENSE). Dependencies retain their own licenses; release bundles include their notices. Audio fixtures are original synthetic test data, with [provenance](tests/fixtures/README.md).
