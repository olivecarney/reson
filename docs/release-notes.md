## Changes in 0.5.4

A native interface polish release, with no new runtime dependencies.

- Refined system typography, sidebar layout, search controls and result feedback.
- Simplified Queue and Library Settings, with clearer empty states and compact layouts.
- Grouped track details into music, audio and file sections, with Reveal in Finder and Copy File Path actions.
- Removed BPM and key columns from track tables; these tags remain in Track Details.
- Play now starts the selected available track, or the first available track in the current list, when nothing is loaded.
- Fixed the lingering outline during mouse seeking. Space now plays/pauses after seeking or changing volume, while text fields and buttons retain normal keyboard behavior.
- Added background-click dismissal for Queue and Settings; Escape also closes Queue.
- Standardized user-facing branding and the app/download names to lowercase `reson`.

Existing library data, playlists, exclusions, artwork cache and preferences remain in their established locations. Replace the previous app when installing this update; no library migration or reimport is required.

## Changes in 0.5.3

- Added local MP3 playback and indexing through Symphonia, with lazy ID3 APIC artwork.
- Ignore macOS metadata sidecars during import.
- Native Settings (⌘,) manages folders, scans and excluded-track restoration.
- Remove selected library tracks or registered folders without deleting music; preserve playlist paths for recovery.
- Isolate test/development databases, artwork and preferences from personal use.
- Added a verified [Homebrew cask](https://github.com/olivecarney/homebrew-tap) for versioned release DMGs.

## Changes in 0.5.2

- Added a drag-to-Applications DMG installer with a checksum.
- Removed the icon's white surround and made its outer background transparent.
- Consolidated CI and releases into one pipeline: build/test/package once, then publish the same verified download.
- Added Rust build caches and refreshed installation and contributor documentation.

## Download and install

Download `reson-0.5.4-macos-arm64.dmg`, open it and drag **reson** to **Applications**. Eject the disk image, then open reson from Applications. Requires Apple Silicon; the app targets macOS 14 or newer. Intel Macs are not supported. Older-system compatibility remains under validation.

The app is ad-hoc signed, not Apple-notarized. After attempting to open a trusted download, use **System Settings → Privacy & Security → Open Anyway** if macOS blocks it.

After verifying the release checksum and copying the app to Applications, Terminal users can remove quarantine for the trusted installed bundle:

```sh
xattr -dr com.apple.quarantine "/Applications/reson.app"
open "/Applications/reson.app"
```

This applies only to reson. For a permissions error, use Open Anyway. See the [first-launch instructions](https://github.com/olivecarney/reson#first-launch-approval) for details.

Use **⌘O** to play a FLAC/WAV/MP3 track or **⇧⌘O** to import your music folder. Library data stays on your Mac.

To verify the download, place the DMG and its `.sha256` file in the same folder and run `shasum -a 256 -c reson-0.5.4-macos-arm64.dmg.sha256` there.

See the README for playback limitations, controls and data locations. Lossless input does not imply bit-perfect output.
