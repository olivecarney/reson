# Reson v0.5 interface

The existing native library, playlists, session queue and audio controls share a compact dark interface. There are no new codecs, dependencies, database migrations, network services or playback policies.

## Layout and appearance

The initial window remains 1180 × 740 points, with an 820 × 520 minimum. Native split panes resize the sidebar between 150 and 200 points and the inspector between 210 and 280. Either panel can be hidden. The centre retains an AppKit table; horizontal scrolling exposes metadata columns when both panels leave limited width. The header uses a native actions menu when the full controls cannot fit. The inspector scrolls independently and caps artwork at 176 points.

Window backgrounds, sidebar/inspector materials, semantic foreground colours, native selection, native focus rings and SF Symbols handle appearance. Shared conventions live in `InterfaceStyle`; no theme engine or animation loop is introduced. Typography remains deliberately compact for a desktop music collection. Large titles truncate in rows and transport, with full row text available through tooltips and accessibility. Inspector titles and metadata/file paths can be selected for copying.

## Library and sidebar

Table rows are 38 points with 28-point artwork, retaining native reuse and asynchronous thumbnail loading. BPM and duration align to the right, including headers. Column widths use native autosaving; the UI does not provide a column configuration system. Library sorting preserves occurrence selection. Playlist headers do not show library sort indicators; returning to Library restores its descriptors. Playing and missing tracks retain explicit text indicators so colour is not the only cue.

Return or keypad Enter plays the first selected occurrence; double-click and the Play context action do the same. Missing occurrences disable Play. Multiple selection, native arrows, command-select/select-all and drag/drop retain their existing behaviour. Context menus use the clicked row unless it is within the selected group. Impossible Move Up/Down actions are disabled. Deselecting all rows clears inspector identity.

Playlists have small native icons and full-name tooltips. Create uses the sidebar plus or ⌘N; rename/delete/export use native context menus or the Playlists menu. Deleting the selected playlist returns to Library, clears stale details and requests focus for the native track table. Renaming preserves playlist identity. Duplicate playlist entries continue to use entry IDs, rather than filenames, for selection and reordering.

## Playback and queue

The transport groups track identity, playback controls and output controls, with 28-point button targets and labelled tooltips. It uses a second control row if the horizontal arrangement cannot fit. Loading displays a small native progress indicator. The timeline retains the v0.4 native NSSlider, generation fencing and background seek implementation. Click/drag seeks; focused arrows seek ±5 seconds and Home/End seek to the bounds. Scrub previews remain separate from incoming positions and cancel on track replacement.

Space toggles playback when focus is in a table or the surrounding window. Text fields, buttons and sliders retain their native Space behaviour. The volume slider, mute restoration and output policies are unchanged. The output menu offers System Default, enumerated devices, refresh and retry. Audio details remain selectable. Fatal output failures offer Retry Output; file failures offer Open File. Nonfatal output notices appear separately from failures, without a misleading Open File action.

The inspector is explicitly labelled Selected Track. Its selection never replaces transport artwork or playback context. Unknown metadata uses an em dash or Unknown artist; no-artwork tracks use the native music-note placeholder.

Queue access is available from the header, sidebar, track context menus and ⌘J. The sheet separates the current playback context from pending occurrences, explains queue priority, and has a useful empty state. Play Next inserts ahead of pending items; Add to Queue appends. Reorder, Delete, Remove and Clear retain existing occurrence identity and session-only persistence. Escape/Done dismiss the sheet. Playing a queued item still uses the established queue operation; no queue persistence is added.

## Keyboard reference

| Action | Shortcut |
| --- | --- |
| Open file / import folder | ⌘O / ⇧⌘O |
| Focus Library search (including from a playlist) | ⌘F |
| Play selected occurrence | Return / keypad Enter |
| Pause / resume outside focused controls | Space |
| Next / Previous | ⌥⌘N / ⌥⌘P |
| Seek on focused timeline | Arrows ±5 seconds; Home/End |
| Create playlist | ⌘N |
| Import / export M3U8 | ⇧⌘I / ⇧⌘E |
| Queue / dismiss queue | ⌘J / Escape |
| Move selected playlist/queue occurrences | ⌥⌘↑ / ⌥⌘↓ |
| Remove selected playlist/queue occurrences | Delete |
| Sidebar / inspector visibility | ⌃⌘S / ⌥⌘I |

Native Tab traversal, selection arrows, context menus, standard text editing and window zoom/fullscreen remain available. No custom context-menu key binding replaces macOS conventions.

## Accessibility and limits

Native tables expose Tracks, Playlists and Pending queue labels. Cell labels include the column and complete value; artwork distinguishes artwork from its placeholder. The timeline exposes position/duration and rejects keyboard input while disabled. Transport buttons expose their purpose and mute value. All Tracks exposes its active selection. Native row selection and menus remain available to accessibility clients.

No custom animations were added, so there is no new reduced-motion exception. The dark appearance remains primary; fonts use fixed desktop sizes rather than a new scalable typography system. Split widths are bounded and adjustable during a session; explicit persistence of pane widths/visibility is not implemented. Full VoiceOver certification, contrast measurement with every system appearance preference, literal pointer dragging and complete keyboard focus traversal remain beyond the verified coverage described in [validation-v0.5.md](validation-v0.5.md).

## Minimal chrome follow-up

The title bar now contains the single lowercase `reson` wordmark. The sidebar wordmark/icon, version/footer slogan, library status strip and FLAC/WAV badge are removed. Version/build information is available through the native **Reson → About reson** panel. Empty sidebar copy is reduced to No playlists. Track counts and actual file-format metadata remain because they describe the collection.

The Time column has a wider default/minimum width and a trailing text inset, including its native header. On macOS 26 and newer the playback-control group uses SwiftUI's native Liquid Glass capsule; earlier systems use a standard material capsule. Reduce Transparency selects an opaque control background. Glass is confined to controls, leaving the dense table flat. See [Apple's Liquid Glass guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).


## Typography and control refinement

The library uses regular 13-point system text and an 18-point medium heading. Inspector labels use sentence case, with a smaller medium title. Timeline labels use the system font with aligned digits. This keeps the native macOS character without adding font assets.

Import, open, queue, inspector and playlist-add actions use native glass capsule buttons on macOS 26+, with nearby effects grouped in a `GlassEffectContainer`. Playback and output controls use matching glass capsules. Earlier systems keep native bordered buttons/materials; Reduce Transparency uses bordered buttons and opaque control surfaces. No animation, shader or rendering dependency is added, and track rows stay flat.
