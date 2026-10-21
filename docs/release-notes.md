## Changes in 0.5.2

- Added a drag-to-Applications DMG installer with a checksum.
- Removed the icon's white surround and made its outer background transparent.
- Consolidated CI and releases into one pipeline: build/test/package once, then publish the same verified download.
- Added Rust build caches and refreshed installation and contributor documentation.

## Download and install

Download `Reson-0.5.2-macos-arm64.dmg`, open it and drag **Reson** to **Applications**. Eject the disk image, then open Reson from Applications. Requires Apple Silicon; the app targets macOS 14 or newer. Intel Macs are not supported. Older-system compatibility remains under validation.

The app is ad-hoc signed, not Apple-notarized. After attempting to open a trusted download, use **System Settings → Privacy & Security → Open Anyway** if macOS blocks it.

After verifying the release checksum and copying the app to Applications, Terminal users can remove quarantine for the trusted installed bundle:

```sh
xattr -dr com.apple.quarantine "/Applications/Reson.app"
open "/Applications/Reson.app"
```

This applies only to Reson. For a permissions error, use Open Anyway. See the [first-launch instructions](https://github.com/olivecarney/reson#first-launch-approval) for details.

Use **⌘O** to play a FLAC/WAV track or **⇧⌘O** to import your music folder. Library data stays on your Mac.

To verify the download, place the DMG and its `.sha256` file in the same folder and run `shasum -a 256 -c Reson-0.5.2-macos-arm64.dmg.sha256` there.

See the README for playback limitations, controls and data locations. Lossless input does not imply bit-perfect output.
