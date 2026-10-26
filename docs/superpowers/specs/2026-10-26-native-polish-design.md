# Native interface polish

User direction: improve the entire UI/UX while keeping reson lightweight. Approved approach: focused native polish; use judgment. Preserve the system font, sidebar-only BPM/key, existing music data, and current native architecture.

## Approach
Refine the existing SwiftUI/AppKit screens. A visual rebuild would increase scope without improving local playback, and new UI packages would work against the lightweight requirement. Keep macOS 14 support, virtualized tables, asynchronous library work, and the existing Rust audio engine.

## Scope
- Consistent hierarchy and spacing, a narrow-sidebar Queue row that does not wrap, and clear, accessible toolbar actions.
- Search with an explicit clear action and useful result/loading feedback.
- Idle Play starts the selected available track, or the first available track in the visible list. Existing playback keeps Play/Pause behavior. Missing tracks, loading, and shutdown remain guarded.
- A compact, bounded Queue with a genuine empty state, count, and short interaction help; preserve native dismissal and row editing.
- A grouped, readable inspector with file actions, clear missing metadata, and a useful unselected state. Keep selected-track details distinct from now-playing details.
- Settings with compact folder/exclusion lists, meaningful empty states, clear path labels, scan feedback, and full access to existing management actions.
- Preserve keyboard navigation, focus, selection, native accessibility, reduced transparency, and error feedback.

## Validation
Behavioral tests for new playback decisions; existing selection, seek, queue, storage, and library tests; rendered compact/normal/empty states; native UI inspection; opt-in synthetic interface benchmarks where practical. No new dependencies, background watchers, network access, or database migration.
