# Using reson

## Install

Download the Apple Silicon DMG from [GitHub Releases](https://github.com/olivecarney/reson/releases/latest). Open it, drag reson to the Applications shortcut, eject the image and launch reson from Applications. For updates, quit reson first and replace the app in Applications; your library and preferences are stored separately.

If macOS blocks a trusted download, attempt to open it and use **System Settings → Privacy & Security → Open Anyway**. Releases are ad-hoc signed and are not notarized. To check a download, keep its `.sha256` file beside the DMG and run `shasum -a 256 -c <download>.dmg.sha256` in that folder.

After verifying the release checksum and copying the app to Applications, Terminal users can remove quarantine for the trusted installed bundle:

```sh
xattr -dr com.apple.quarantine "/Applications/reson.app"
open "/Applications/reson.app"
```

This applies only to reson. For a permissions error, use Open Anyway. See the [first-launch instructions](../README.md#first-launch-approval) for details.

MP3 playback, native Settings and library management are available starting in version 0.5.3.

## Add music

Use **File → Open File…** (**⌘O**) to play a FLAC, PCM WAV or MP3 file. Files opened this way are session-only unless they are already in the library.

Use **File → Import Folder…** (**⇧⌘O**) to index a folder and its subfolders. reson records metadata and file locations without copying or modifying your music. Symlinks are skipped. You can cancel an import; tracks already indexed remain available.

Folder imports and playlists persist between launches. Select **File → Rescan Folders** after adding or changing files. There is no automatic folder watcher. Missing files remain marked in the library; moved or renamed files are indexed at their new paths rather than automatically relinked. Unsupported or unreadable files are skipped during import.

## Settings and library removal

Open **reson → Settings…** with **⌘,**. General contains playback volume, mute and version information. Library lists registered folders, offers Add Folder, Remove Folder and Rescan Folders, and shows scan progress and cancellation. **reson → About reson** opens the standard macOS About panel.

Select one or more indexed tracks in All Tracks (up to 1,000 at a time), right-click and choose **Remove from Library…**, then confirm. Only database records are removed; original files stay on disk. Current playback and queued sources continue independently. Playlist entries remain in their original order and show Missing until restored.

Removed tracks are excluded by their canonical path. Exclusions persist across rescans, restarts and file replacements at that path. In Library Settings, select an excluded path and choose **Restore Track** to clear its exclusion and rescan registered folders. Missing or unreadable sources can be restored when available. A new filename is a new path and can be imported normally. Opening a file directly plays it without restoring its indexed record.

Removing a folder keeps tracks covered by other registered folders, including nested sources. It also preserves playlists and all original files. Exclusions stay while another source covers them; removing their last covering folder clears them, so adding that folder again performs a fresh import. Wait for a scan to finish or cancel it before removing tracks or folders.

AppleDouble `._*` sidecars, `.DS_Store` and `__MACOSX` directories are ignored before audio probing. Genuine corrupt audio still reports an import error.

## Browse and play

Search the library with **⌘F**. Search covers titles, artists, albums, genre and file paths. Click column headers to sort. Clear the search with its × button or Escape; press Return in search to move keyboard focus to the results. Matching of non-ASCII text is limited by SQLite's case-insensitive comparison rules.

Double-click a track, select it and press **Return**, or choose **Play** from its context menu. Missing tracks cannot be played. The inspector follows your selection; the playback bar follows the currently playing track. These can show different tracks. Track Details groups tags and audio properties and offers Reveal in Finder and Copy File Path. BPM and key are shown here instead of in the track table.

Artwork comes from embedded FLAC pictures or supported WAV/MP3 ID3 APIC tags. reson does not fetch covers online. Unsupported or missing images show a placeholder. Rescan after replacing embedded artwork.

## Playback controls

Use Play/Pause or **Space** to pause and resume; Space also works after seeking or adjusting volume; text fields and buttons retain their normal keyboard behavior. When nothing is loaded, Play starts the selected available track, or the first available track in the visible list. Stop releases playback resources and resets position. Play after Stop starts the track again from the beginning.

Click or drag the timeline to seek. With the slider focused, arrow keys seek by five seconds; Home and End move to the start and end. Volume and mute affect reson only, and are saved between launches.

Use the speaker device menu to choose **System Default** or a specific output. Each launch starts with System Default. Explicit output selections last for the session and do not silently fall back when a device disappears. Refresh Devices updates the list. Reconnect a missing device and use **Retry Selected Output**, or choose another output. Recovery can leave the track paused; press Play when ready.

The audio-details control shows source properties separately from the opened output stream. Rate or channel conversion can occur even with lossless files. See [audio behaviour](audio.md).

## Playlists and queue

Create a playlist with **⌘N**. Use its context menu or the Playlists menu to rename, delete or export it. Deleting a playlist does not delete music files. Duplicate entries are allowed and can be moved independently.

Select tracks and use drag/drop or the context menu to add them to a playlist. Reorder playlist or queue entries with **⌥⌘↑** and **⌥⌘↓**; **Delete** removes selected entries from that list.

**Play Next** puts tracks ahead of normal sequence playback. **Add to Queue** appends them. Open the queue with **⌘J** to inspect, reorder, remove or clear pending entries. Click the main window behind Queue to dismiss it, or press Escape. The queue is temporary and starts empty after relaunch; playlists are saved.

Use **⇧⌘I** to import a local UTF-8 M3U8 playlist and **⇧⌘E** to export the selected playlist. Playlist exchange refers to local files; it does not copy audio or stream remote URLs.

## Keyboard reference

| Action | Shortcut |
| --- | --- |
| Open file | ⌘O |
| Import folder | ⇧⌘O |
| Search library | ⌘F |
| Play selection | Return |
| Pause / resume | Space (including focused seek/volume sliders) |
| Create playlist | ⌘N |
| Import / export M3U8 | ⇧⌘I / ⇧⌘E |
| Show queue | ⌘J |
| Next / previous track | ⌥⌘N / ⌥⌘P |
| Move playlist / queue selection | ⌥⌘↑ / ⌥⌘↓ |
| Remove playlist / queue selection | Delete |
| Toggle sidebar | ⌃⌘S |
| Toggle inspector | ⌥⌘I |

Drag the pane dividers to resize the sidebar and inspector. At smaller window sizes, toolbar actions can move into the overflow menu and the track table scrolls horizontally.

## Local data and troubleshooting

- Library and playlists: `~/Library/Application Support/Reson/library.db`.
- Artwork cache: `~/Library/Caches/Reson/Artwork/`.
- Volume and mute: macOS application preferences for `dev.reson.player`.

To back up the library, quit reson before copying its application-support directory. Deleting the library database removes saved imports and playlists, not audio files. The artwork cache can be deleted while reson is closed; thumbnails regenerate when needed.

For a missing track, check that its drive is mounted and its original path exists, then rescan. For silence, check reson mute/volume, the selected output and macOS output settings. Try another known-good FLAC/WAV/MP3. Report reproducible problems through the [issue tracker](https://github.com/olivecarney/reson/issues), including app/macOS versions, audio format and output device. Remove private paths from logs and screenshots.
