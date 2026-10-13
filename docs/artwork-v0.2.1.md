# Artwork and interface polish v0.2.1

Artwork is a native Swift service, independent of the Rust playback and library workers. No Rust dependency, C ABI change, database migration or full-resolution image column is introduced. The schema stays at version 1 and existing IDs/folder records remain intact.

## Extraction

`EmbeddedArtwork` reads FLAC metadata block headers and picture blocks. It prefers front covers and falls back to another embedded picture. For RIFF/WAVE it seeks over audio/unknown chunks and reads conventional `id3 `/`ID3 ` chunks with ID3v2.3/v2.4 APIC frames. Single-byte and UTF-16 descriptions are supported. External image links are never followed. Compressed/encrypted/grouped/unsynchronised frames and extended/flagged tags, ID3v2.2, RF64 and proprietary WAV artwork conventions produce absence. Unsupported/corrupt images use a placeholder.

Limits: 8 MiB image payload, 32 MiB accumulated picture/tag reads, 4,096 metadata blocks/chunks/frames, 1 KiB MIME string and 64 KiB picture description. ImageIO inspects dimensions before creating a thumbnail: maximum 8,192 pixels per axis and 32 megapixels. No audio samples are decoded or large data chunks read. Reads and seeks are bounded by the source length; truncated inputs return absence.

The library scanner already configures Symphonia to allocate zero visual bytes. A narrowly scoped native reader avoids adding image-buffer ownership to the C ABI, changing that scanner, or doing another full audio-format probe. No new package is needed. Format references: [FLAC specification](https://xiph.org/flac/format.html#metadata_block_picture), [ID3v2.3](https://id3.org/id3v2.3.0), [ID3v2.4](https://id3.org/id3v2.4.0-structure).

## Cache and lifetime

`ArtworkCache` owns a utility dispatch queue. Extraction, stat, ImageIO inspection/resize/decode, encoding, reads and atomic writes all run on that queue. Its default disk directory is `~/Library/Caches/Reson/Artwork/`; tests inject temporary directories. SHA-256 keys include format version, standardized absolute path, device/inode, source size and nanosecond modification/change times. They are checked again before writing a new result, so a source replaced during extraction cannot populate an old key. Current source existence is checked even on a memory hit.

80-pixel PNGs serve table and transport. A thumbnail up to 384 pixels is created only for an open inspector. When a large cached thumbnail already exists, it can supply the smaller one without another metadata read. No full-resolution image is saved. Validated `.none` markers persist absence/invalid-image results across sizes and launches. Missing/unreadable sources fail gracefully. Corrupt/truncated/oversized cache files are regenerated from the source. Cache write failure still returns the decoded thumbnail. The memory LRU has hard limits of 128 entries (including absent images) and 8 MiB decoded pixel cost. Cached PNG reads are limited to 1 MiB.

Repeated requests serialize and hit the memory/disk cache rather than duplicating the same extraction. Cancellation skips obsolete queued operations; already-running bounded work can finish. Application shutdown immediately closes admission, drains the artwork queue and releases its memory, alongside the existing audio/database shutdowns. No artwork timer or background scan remains active while idle.

Stale keys become unreachable when source identity changes. There is no automatic disk eviction; obsolete files may accumulate until the OS/user clears this disposable cache. Filesystem stalls can still delay a running read or shutdown on that queue. There is no new filesystem watcher: manual rescan refreshes currently visible artwork and the inspector/transport; reopening/reselecting/reusing a view requests current source identity. A file modified externally without any of those events may remain displayed until refreshed.

## Presentation

The AppKit table retains its 48-point rows, columns and native selection/keyboard/sort behavior. Artwork occupies a fixed 36-point square with rounded corners and a restrained native music-note placeholder. NSTableView requests cells only as they become visible/near-visible. Each recycled artwork cell cancels its old task, clears its image/tint, increments a request token and checks token/path before installing a result. Image arrival updates the image view directly without table reload. Import/rescan completion refreshes only visible artwork cells; metadata/search/sort follow existing table updates.

`ArtworkLoader` uses a generation fence. SwiftUI artwork views hide images whose requested path differs from the current path and cancel superseded tasks. Inspector artwork follows selected track; transport artwork follows playback independently. Inspector metadata is selectable, with bounded title/artist lines and missing-value placeholders. The header falls back to two rows in narrow windows, transport titles truncate, and empty search results offer Clear Search. The sidebar and native dark styling remain compact.

## Validation

See [v0.2.1 validation](validation-v0.2.1.md) for automated, native and performance evidence. Existing v0.2 playback-output investigation remains authoritative for output notices/failures. Artwork errors neither enter the playback queue nor change library indexing outcomes.
