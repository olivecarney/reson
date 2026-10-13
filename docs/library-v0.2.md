# Persistent library v0.2

Reson uses rusqlite 0.40.2 against macOS system SQLite, without bundled SQLite or Turso. The historical Turso spike is preserved at e26a693 and in docs/spikes. See system-sqlite.md for the decision and footprint comparison.

## Ownership and threading

LibraryStore owns one SQLite connection on a dedicated Rust library worker. The audio worker and its bounded queue remain independent. A separate Swift LibraryBridge queue owns the library C handle, database path setup, requests, copied JSON responses and destruction. UI tasks await these calls; no database, scanner, filesystem existence check or engine join runs on the SwiftUI main actor. Startup creates the library under `~/Library/Application Support/Reson/library.db`. `RESON_LIBRARY_PATH` overrides the location for isolated tests.

The four library C functions create/request/read/destroy are serialized per handle. Query responses contain at most 500 records, retained unchanged between the sizing and copying calls. Inputs have byte bounds; sort names come from a fixed allowlist; searches bind SQL parameters and escape LIKE wildcard characters. Swift fences query results by request ID and database revision, preventing a superseded search from replacing newer results. It collects pages for the native table; UI memory therefore scales with library size. Playback has its existing independent load-generation fence.

## Persistence and scanning

Schema version 1 has denormalized tracks and imported folders, unique canonical absolute paths and stable row IDs. Track records include title, artist, album, genre, duration, rate, channels, bit depth, format, tagged BPM/key, file size/mtime/import timestamp and missing state. Folders retain import and last completed scan timestamps. Title/artist/album indexes use NOCASE. Initial migration is transactional. Newer schema versions and malformed schemas are rejected; corrupt databases are not silently replaced.

WAL and synchronous FULL make each successful track upsert a committed unit. Cancellation or shutdown keeps previous successes; reimport/rescan safely upserts again. The scanner walks recursively and sequentially, skipping symlinks to avoid loops and indexing FLAC/WAV headers without decoding audio or allocating artwork. Queries/cancellation are checked between files. Directory enumeration, a single header read, final missing reconciliation, a busy database or stalled filesystem operation can delay a library command; the main actor and audio queue remain available.

A completed readable scan marks genuinely absent files as missing without deleting records. An inaccessible root or incompletely enumerated subtree does not infer deletions. Disconnected drives preserve their library entries. Missing state reflects the last successful manual scan; launching does not touch every audio file. Restored files clear missing state on rescan. Paths define identity: a rename/move imports a new row and leaves the old row missing; no fingerprint-based relinking is attempted. Overlapping folder imports share the same unique canonical file path.

Malformed/unsupported/unreadable files are skipped. Counts and the latest failure are shown; the summary is bounded rather than retaining a log entry for every failure. Missing files fail playback gracefully; selecting a valid file recovers. Metadata values remain unknown when not tagged: no BPM/key estimation or artwork extraction. SQLite LIKE/NOCASE case folding is ASCII; exact Unicode text and paths work, but full Unicode case-insensitive matching is deferred.

## Native interface

Import Folder (Shift-Command-O), search, native sortable headers, rescan (File menu or completed-import bar), cancellation and missing indicators extend the existing AppKit table. Selection remains separate from playback. The inspector shows genre and tagged BPM/key. Search includes title, artist, album, genre and path/filename. Sorting supports title, artist, album, BPM, key, duration and format with stable ID ties. Individual Open File (Command-O) still plays directly; those unimported session entries are not persisted and appear after saved query results. Artwork, playlists, seeking, gapless playback and device selection remain deferred.

## Reproduction

Run the normal Rust tests, Swift tests and release build as described in README. Tests use temporary databases and synthetic fixtures, never the user's Application Support library.

`cargo run --release --example library_bench -- build/library-bench` seeds 270/5,000/25,000 metadata records, measures reopen/query/pagination/size, and imports 270 small original WAV fixtures. To measure the complete Swift bridge, set `RESON_BENCHMARK_DATABASES="$PWD/build/library-bench"` when running `swift test --package-path macos --filter LibraryBridgeTests`.

The historical Turso query source is archived in docs/spikes/turso-source/warm_queries.rs. Compile it in a disposable Cargo project with turso 0.8.3 (defaults disabled) and pollster 0.4, then run from the repository root after library_bench. It copies the synthetic SQLite databases into build/turso-bench. This comparison adds no Turso dependency to Reson.
