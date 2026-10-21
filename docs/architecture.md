# Architecture

Reson uses a native SwiftUI/AppKit interface over a Rust audio and library engine. There are no runtime network services or external Swift package dependencies.

```text
SwiftUI / AppKit
  ├─ EngineBridge queue → Rust playback worker → rodio / cpal / CoreAudio
  ├─ LibraryBridge queue → Rust library worker → LibraryStore / system SQLite
  └─ ArtworkCache queue → bounded metadata reader / ImageIO / thumbnail cache
```

## Source layout

| Path | Responsibility |
| --- | --- |
| `crates/engine/src/` | Playback, metadata, library store/scanner/worker and C exports |
| `crates/engine/tests/` | Decoder, bridge, storage, playlist and crash-recovery tests |
| `crates/engine/examples/` | Opt-in diagnostics and benchmarks |
| `macos/App/` | Lifecycle, observable state, bridge ownership and playback coordination |
| `macos/App/Artwork/` | Embedded artwork extraction, loading and cache |
| `macos/Views/` | SwiftUI composition and AppKit tables/controls |
| `macos/Bridge/` | C header and Swift module maps |
| `macos/Resources/` | Original app icon artwork |
| `scripts/` | Build, packaging, checks and fixture generation |
| `tests/fixtures/` | Small synthetic audio fixtures |

## Playback and the C bridge

A dedicated Rust worker owns playback resources and accepts a bounded command queue. File opening, device setup, seek preparation and shutdown run off the main UI thread. Load/Stop generations fence stale work; seeks also carry sequence identity. Swift owns the current sequence, history and explicit queue. Only a completed track advances the sequence; Stop, seek and failures do not impersonate EOF.

`EngineBridge` serializes calls and destroys the engine on a background queue. Shutdown is terminal and idempotent. The [C header](../macos/Bridge/include/reson.h) defines pointer ownership, buffer sizing, status codes and threading. Keep backend-specific rodio types inside Rust. See [audio behaviour](audio.md) for output and callback limits.

## Library and playlists

`LibraryStore` owns system SQLite through rusqlite, without bundled SQLite. One dedicated worker owns its connection and scans between command checks. `LibraryBridge` owns the C handle and copies paged JSON responses on a separate serial queue. UI requests use request identity and database revision to reject stale results.

Schema version 3 stores imported folders, track metadata, playlists, playlist entries and path-level library exclusions. Canonical paths identify tracks. Playlist entries have their own IDs so duplicates are independent; retained paths protect against stale track references. Migrations are transactional. Newer or malformed schemas are rejected rather than silently replaced.

WAL and synchronous FULL preserve completed writes across cancellation and interruption. Searches bind parameters and use a fixed sort allowlist. Responses contain at most 500 records per page; the Swift model collects pages for its table, so UI memory grows with library size. Case-insensitive matching uses SQLite's ASCII rules.

The scanner recursively indexes FLAC/WAV/MP3 metadata without decoding audio or loading artwork, skips symlinks, and upserts completed files independently. Cancellation is checked between files. A blocked filesystem operation or busy database can delay a command. Missing files remain in the library; automatic file watching and moved-file relinking are not implemented.

## Artwork

Artwork extraction is independent of Rust playback and database indexing. A bounded reader handles FLAC picture blocks and supported WAV/MP3 ID3/APIC tags. It never follows external artwork links. ImageIO validates dimensions and produces thumbnails; invalid or unsupported images fall back to a placeholder.

`ArtworkCache` performs reads, resizing and atomic disk writes on its utility queue. Keys include source identity and modification metadata, checked again before publication. Requests use 80-pixel thumbnails for tables/transport and up to 384 pixels for the inspector. Absence markers avoid repeatedly probing files without artwork.

The memory cache is limited to 128 entries and 8 MiB of decoded pixels. Opportunistic disk maintenance prunes recognized files above 256 MiB towards 192 MiB, throttled to once per day. Startup does not scan the cache. Maintenance yields between batches and avoids following symlinks or removing newly published/replaced files.

Reused cells and SwiftUI loaders cancel obsolete requests and check identity before displaying results. Image updates do not reload the whole table. Manual rescan refreshes visible artwork. Shutdown stops admission and drains in-flight work.

## App icon and bundle

`macos/Resources/AppIcon.icon/Assets/AppIcon.png` is the transparent app artwork. Pixels outside the dark tile must stay transparent to avoid a white border. `scripts/build-icon.sh` generates standard 16–1024 pixel representations and writes `AppIcon.icns` into the app's Resources directory. `CFBundleIconFile` in `macos/Info.plist` registers it with macOS. `AppIcon.icon/icon.json` defines the native macOS 26+ icon composition; `actool` compiles it to `Assets.car`, selected by `CFBundleIconName`. This avoids the pale compatibility frame applied to legacy icons. The `.icns` remains available on older macOS releases. The build includes dependency license notices and signs the completed bundle after all resources are added. Generated icon files stay under ignored `build/`.

## Distribution pipeline

The single GitHub Actions workflow builds and validates on macOS, then packages a read-only drag-to-Applications DMG. A separate lightweight job publishes the artifact from the same run for new versions on `main`. It does not rebuild the app. See the [release guide](releases.md) for versioning, caches, permissions and recovery.

Library removal runs transactionally on the existing Rust library worker. Folder ownership is computed from canonical path components; no prefix matching or filesystem deletion is used. Exclusions are loaded into a scan-local set once per scan. Playlist paths reconnect missing references on reimport.
