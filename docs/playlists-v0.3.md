# Playlists and playback in v0.3

Playlists persist in the existing library database. The explicit queue is in-session and starts empty after relaunch. All operations remain local and offline.

## Storage and identity

Schema version 2 adds `playlists` (stable ID, name, revision) and `playlist_entries` (stable entry ID, playlist ID, nullable library track ID, retained path/title/duration and position). Duplicate tracks have distinct entry IDs. Foreign keys cascade playlist deletion and set deleted track references to NULL. Query resolution also checks the retained path, protecting against externally reused track IDs.

The existing Rust library worker owns the existing SQLite connection. Migration from version 1, insertion, removal and reorder are transactional. Migration preserves track/folder IDs and metadata, and rolls back if interrupted before commit. WAL and synchronous FULL remain in use. Reopen completes an interrupted migration; corruption and failed writes surface errors rather than replacing the database.

Missing entries stay visible. Manual folder import/rescan can restore their indexed path. Moved or renamed files require explicit management; there is no fingerprinting or automatic relinking. Queries return at most 500 rows per page. Persistent edit requests and app-local drag payloads accept at most 1,000 selected IDs. Revisions reject stale editing. Reorder is an O(N) transaction over entry IDs, without reading the full library's metadata.

## Playback and queue

Double-clicking a library track captures the visible search/sort order; double-clicking a playlist captures its stored order, starting at that occurrence. Navigation, search, sort, playlist edits and removal of the playing entry do not rewrite this captured sequence or interrupt its current audio. Inspector selection is independent of transport artwork and playback identity.

Play Next places selected items ahead of the remaining explicit queue, preserving selection order. Add to Queue appends. Duplicates play separately. A queued occurrence is consumed only when its playback begins successfully; a reserved occurrence survives replacement before it starts. Starting another visible sequence retains the explicit queue and resets history. Queue items take precedence over ordinary progression, which resumes at its saved cursor afterwards.

Next consumes the queue first, otherwise advances the sequence (or forward history after Previous). Previous visits successfully confirmed playback history, capped at 1,000 occurrences; it does not seek or restart based on elapsed time. Taking an explicit queue item after Previous forks forward history. At sequence boundaries the action gracefully does nothing. Missing/invalid items are skipped through bounded attempts; an output-device failure halts progression. Clear/remove/reorder of pending queue items do not interrupt current playback.

Natural EOF advances once using generation and acknowledged-command fences. Stop, replacement, fatal output failure and terminal shutdown cannot masquerade as EOF. Swift command request IDs also reject late, out-of-order tasks. One audio engine and one output stream remain in use. Existing snapshot polling runs while active and stops when idle; SQLite and file/device work stay off the main actor.

## Native interactions

The sidebar supports selection, creation, context-menu rename/delete/export and dropping selected library rows onto a playlist. Delete requires confirmation. The central AppKit table supports multiple-row insertion/reorder and keeps entry identity distinct from track identity. The queue sheet reuses the native table; double-click starts a queued occurrence. Row context menus provide Play Next, Add to Queue, Add to Playlist, removal and queue access.

| Action | Shortcut |
| --- | --- |
| Create playlist | ⌘N |
| Import / export M3U8 | ⇧⌘I / ⇧⌘E |
| Show queue | ⌘J |
| Next / previous | ⌥⌘N / ⌥⌘P |
| Move selected playlist or queue rows | ⌥⌘↑ / ⌥⌘↓ |
| Remove selected playlist or queue rows | Delete |
| Pause / resume | Space |

## M3U8 policy

Import accepts UTF-8 (optional BOM), `#EXTM3U`, `#EXTINF`, comments and absolute or relative local FLAC/WAV paths. Relative paths resolve against the playlist's directory, including existing symlink parents. Order and duplicates are retained. All URI schemes, including `file:`, unsupported extensions and unsafe control paths are skipped and reported. Invalid UTF-8 fails the operation. Input is capped at 16 MiB and 100,000 accepted entries.

Unindexed or missing local paths remain as recoverable missing entries, with available EXTINF metadata. Import does not scan arbitrary folders. Explicitly import the music folder to make those paths playable through the library.

Export writes UTF-8 EXTINF entries in stored order, including duplicates and missing paths. Paths inside the destination directory use `./` relative form; others remain absolute. Metadata line breaks are normalised. Paths containing unsafe controls/newlines or trailing whitespace fail export rather than producing ambiguous data. An exclusive temporary file is synced and atomically renamed, followed by parent-directory sync. Failed temporary creation never deletes a pre-existing collision file.

Seeking, shuffle, repeat, gapless playback, queue persistence, cross-application drops, file watching and moved-file detection are deferred. Existing CoreAudio conversion and older-macOS compatibility limits are unchanged; see the README and validation record.
