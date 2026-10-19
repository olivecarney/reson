# Reson v0.5 interface

The existing native library, playlists, session queue and audio controls share a compact dark interface. There are no new codecs, dependencies, database migrations, network services or playback policies.

## Layout and appearance

The initial window remains 1180 × 740 points, with an 820 × 520 minimum content frame (the native title bar adds height). Native split panes resize the sidebar between 150 and 200 points and the inspector between 210 and 280. Either panel can be hidden. The centre retains an AppKit table; horizontal scrolling exposes metadata columns when both panels leave limited width. Window actions use the native toolbar and its standard sizing/overflow behaviour; the content header contains only the list title/count and library search. The inspector scrolls independently and caps artwork at 176 points.

Window backgrounds, sidebar/inspector materials, semantic foreground colours, native selection, native focus rings and SF Symbols handle appearance. Shared conventions live in `InterfaceStyle`; no theme engine or animation loop is introduced. Typography remains deliberately compact for a desktop music collection. Large titles truncate in rows and transport, with full row text available through tooltips and accessibility. Inspector titles and metadata/file paths can be selected for copying.

## Library and sidebar

Table rows are 38 points with 28-point artwork, retaining native reuse and asynchronous thumbnail loading. BPM and duration align to the right, including headers. Column widths use native autosaving; the UI does not provide a column configuration system. Library sorting preserves occurrence selection. Playlist headers do not show library sort indicators; returning to Library restores its descriptors. Playing and missing tracks retain explicit text indicators so colour is not the only cue.

Return or keypad Enter plays the first selected occurrence; double-click and the Play context action do the same. Missing occurrences disable Play. Multiple selection, native arrows, command-select/select-all and drag/drop retain their existing behaviour. Context menus use the clicked row unless it is within the selected group. Impossible Move Up/Down actions are disabled. Deselecting all rows clears inspector identity.

Playlists have small native icons and full-name tooltips. Create uses the sidebar plus or ⌘N; rename/delete/export use native context menus or the Playlists menu. Deleting the selected playlist returns to Library, clears stale details and requests focus for the native track table. Renaming preserves playlist identity. Duplicate playlist entries continue to use entry IDs, rather than filenames, for selection and reordering.

## Playback and queue

The transport groups track identity, playback controls and output controls, with 28-point secondary targets, a larger Play/Pause target and labelled tooltips. It uses a second control row if the horizontal arrangement cannot fit. Loading displays a small native progress indicator. The timeline retains the v0.4 native NSSlider, generation fencing and background seek implementation. Click/drag seeks; focused arrows seek ±5 seconds and Home/End seek to the bounds. Scrub previews remain separate from incoming positions and cancel on track replacement.

Space toggles playback when focus is in a table or the surrounding window. Text fields, buttons and sliders retain their native Space behaviour. The volume slider, mute restoration and output policies are unchanged. The output menu offers System Default, enumerated devices, refresh and retry. Audio details remain selectable. Fatal output failures offer Retry Output; file failures offer Open File. Nonfatal output notices appear separately from failures, without a misleading Open File action.

The inspector is explicitly labelled Selected Track. Its selection never replaces transport artwork or playback context. Unknown metadata uses an em dash or Unknown artist; no-artwork tracks use the native music-note placeholder.

Queue access is available from the toolbar, sidebar, track context menus and ⌘J. The sheet separates the current playback context from pending occurrences, explains queue priority, and has a useful empty state. Play Next inserts ahead of pending items; Add to Queue appends. Reorder, Delete, Remove and Clear retain existing occurrence identity and session-only persistence. Escape/Done dismiss the sheet. Playing a queued item still uses the established queue operation; no queue persistence is added.

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

## Native macOS design correction (15 October 2026)

Window actions now live in the real unified window toolbar: sidebar, import, open, queue and inspector, with export when a playlist is active. These standard toolbar controls adopt the platform appearance, including Liquid Glass on modern macOS; no extra glass modifier is placed on them. The lowercase `reson` title uses the system window-title typography. The sidebar wordmark, version/footer slogan and format badge stay removed. Version/build information remains in **Reson → About reson**.

### Material hierarchy

- Library and playlist content use `NSColor.textBackgroundColor`. Rows, artwork and metadata have no glass, gradients, shadows or per-row cards. AppKit owns selection and focus. Numeric columns use aligned system digits, and emphasized cells adopt `alternateSelectedControlTextColor`, restoring their normal semantic colour when focus/selection changes.
- Navigation uses one AppKit `NSVisualEffectView` with `.sidebar` material and behind-window blending. All Tracks and playlists both use native source-list rows; there is no custom translucent blue selection rectangle. The existing `HSplitView` and pane visibility/state remain intact.
- Inspector content uses `NSColor.windowBackgroundColor`, rather than another large material layer. Its scrolling metadata remains flat, selectable and separated with native dividers. Artwork stays bounded at 176 points.
- Transport uses one native `.titlebar` material with within-window blending. Only the playback group gets a custom SwiftUI `.glassEffect(.regular, in: .capsule)`, contained by `GlassEffectContainer`. Play/Pause has a larger system symbol and target. Volume, device selection and audio details remain standard controls without a second glass capsule. Timeline and volume retain their native sliders.
- Sheets, menus and popovers use system presentation. No simulated blur or duplicate custom background is added to these surfaces.

The SDK declarations mark `glassEffect` and `GlassEffectContainer` available from macOS 26. The deployment target remains macOS 14; earlier systems take the availability-guarded native regular-material playback fallback and standard AppKit toolbar/sidebar materials. Reduced transparency or increased contrast removes custom playback glass and hides the sidebar/transport visual effect, replacing each with an opaque semantic background. Preference changes restore the same effect view, avoiding stacked materials. System toolbar/menu accessibility treatment remains system-owned.

### Typography and appearance policy

San Francisco comes exclusively from system font APIs. Library headings are 18-point medium; track rows are 13-point regular with primary title/secondary metadata colours; inspector titles are 16-point medium; transport titles are 13-point medium. Ordinary metadata, timestamps and small labels are at least 12 points where explicitly sized. SwiftUI timestamps use `monospacedDigit`; AppKit duration/BPM cells use `monospacedDigitSystemFont`. General labels stay proportional. The Time column keeps its wider minimum and trailing inset.

Reson remains deliberately dark-first. SwiftUI's preferred dark scheme is retained and AppKit's application appearance is dark Aqua so tables, native menus, file panels and About presentation follow the same policy. Backgrounds and labels are semantic system colours, not sampled RGB values. There are no custom font files, rendering loops or new dependencies. Native high-contrast controls and opaque fallbacks were exercised on the development system; older macOS execution and full VoiceOver certification remain unverified.

The corrected empty-window layout also applies disabled seek state through SwiftUI and AppKit; parent environment updates can otherwise override the embedded slider's initial AppKit state.

This follows [Apple’s Liquid Glass adoption guidance](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) and [custom-view guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views): use standard controls first and confine additional glass to the functional control layer. See [validation-v0.5.md](validation-v0.5.md) for actual visual and performance evidence and its limits.
