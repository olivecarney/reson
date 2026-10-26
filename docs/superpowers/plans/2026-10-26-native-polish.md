# Native Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Improve everyday browsing and playback while preserving reson's native, lightweight design.
**Architecture:** Refine existing SwiftUI screens and AppKit table integrations. Add only small model presentation decisions; retain asynchronous library access and virtualized tables.
**Tech Stack:** SwiftUI, AppKit, existing Rust engine; no new dependencies.
**Spec:** `docs/superpowers/specs/2026-10-26-native-polish-design.md`

## Global Constraints
- macOS 14 support; no new dependencies, migrations, network services, or watchers.
- Preserve previous scrubbing/dismissal fixes, sidebar-only BPM/key, and system typography.
- Work in the existing checkout so the user's uncommitted UI fixes remain included; no branch integration or publication.

## Review Focus
- Idle Play must not choose missing rows; loaded playback must remain independent of selection.
- Narrow sidebar and 820×520 windows must keep actions usable.
- Search changes must preserve debouncing and keyboard focus.
- Empty queue/settings states must not hide essential actions.
- Large libraries must keep lazy AppKit rendering and bounded work per update.

### Task 1: Playback affordance
Files: PlayerModel.swift, ResonApp.swift, TransportView.swift, TransportTests.swift.
- [x] Write and run failing tests for idle selected/first available/missing tracks and loaded-track precedence.
- [x] Implement `playbackStartRow: PlaybackSnapshot?` and `canTogglePlayback: Bool`; route idle `togglePlayback()` through `playRow`.
- [x] Apply consistent enablement to transport and menu; verify behavior tests.

### Task 2: Main window and inspector
Files: ContentView.swift, InterfaceStyle.swift, InspectorView.swift, PlaylistSidebar.swift.
- [x] Refine sidebar Queue row, search clear control and result status, toolbar help and selected state.
- [x] Group inspector metadata; provide Reveal in Finder and Copy File Path through native APIs; preserve metadata/selection identity.
- [x] Run layout, selection, and accessibility checks with rendered evidence.

### Task 3: Queue and Settings
Files: QueueView.swift, SettingsView.swift, InterfaceLayoutTests.swift.
- [x] Bound Queue size, show count and empty state without redundant table chrome, retain editing for populated queue.
- [x] Group Settings content, concise empty lists and path rows, clear scan controls and feedback.
- [x] Verify empty/populated and compact layouts; keep dismissal behavior.

### Task 4: Verification and delivery
- [x] Run full Swift tests and synthetic native interface benchmarks.
- [x] Review changes with a fresh reviewer; resolve actionable findings.
- [x] Build the app; inspect native UI and relaunch latest build.

## Execution ledger
- Ruling: work in place — previous requested changes are uncommitted here and must be retained.
- Ruling: user's “use your judgment” authorizes routine design decisions and continuous implementation.

- Verification: initial full Swift suite passed 106 tests, 9 optional skips. Native interface benchmark passed at 270/5,000/25,000 tracks, median scroll+layout about 2.5 ms; synthetic evidence does not measure audio continuity or total memory.
- Review: fresh reviewer identified empty-playlist overlay hit testing as a drag/drop risk. Restored passthrough for playlist and loading overlays, retaining hit testing only for interactive library empty states.

- Final verification: 106 Swift tests, 9 optional skips, zero failures; release build succeeded. Live UI checked search/clear/results count, Return-to-table focus, inspector, empty Queue/Escape, and Library Settings. Latest build left running with full library search restored.
