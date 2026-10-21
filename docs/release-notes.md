## Changes in 0.5.1

- Added the Reson app icon to Finder, the Dock and app bundles.
- Reworked documentation for users and contributors.
- Removed obsolete development reports and dependency experiments.

## Download and install

Download `Reson-<version>-macos-arm64.zip`, unzip it and drag **Reson.app** to **Applications**. Requires Apple Silicon; the app targets macOS 14 or newer. Intel Macs are not supported. Older-system compatibility remains under validation.

This early release is ad-hoc signed, not Apple notarized. After attempting to open it, use **System Settings → Privacy & Security → Open Anyway** if macOS blocks it. Only approve a download you trust. No Developer ID certificate is included.

Use **⌘O** to play a FLAC/WAV track or **⇧⌘O** to import your music folder. Library data stays on your Mac.

A `.sha256` file accompanies the archive. In the download directory run `shasum -a 256 -c Reson-<version>-macos-arm64.zip.sha256` to verify it.

See the README for playback limitations, controls and data locations. Lossless input does not imply bit-perfect output.
