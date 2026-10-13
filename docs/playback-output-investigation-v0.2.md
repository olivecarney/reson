# v0.2 playback output-event investigation

2026-10-13, native execution on Apple Silicon/macOS 27.0.1. Work remains local on reson-v0.2; no merge, tag or push.

## Reproduction and cause

The pre-merge failure used `build/premerge/native/music/02 - Tone.wav`, a 30-second original synthetic 24-bit stereo/44.1 kHz WAV imported into the isolated test library. The default output was AirPods Pro, reporting 48 kHz stereo. No device settings were changed during this investigation.

The unchanged v0.1.1 native app reproduced the generic output failure with the same file/device and no library worker or database. A standalone v0.2 engine lifecycle check passed. Inspection confirmed v0.2 had changed only metadata probing/normalization in playback.rs; output construction, OS-default buffer configuration and callback handling were inherited from v0.1.1.

Initially every CPAL callback set one shared Boolean. The worker interpreted that Boolean as a fatal error and discarded the underlying event. Diagnostic capture reproduced the native failure with:

```
Output stream callback (DeviceChanged): default output device changed
```

The failure happened after stream initialization, during playback. CPAL 0.18.2 defines DeviceChanged as an already completed automatic reroute with a valid active stream; rebuilding is unnecessary. Xrun indicates a possible glitch, and RealtimeDenied indicates degraded scheduling rather than a dead stream. See the [pinned CPAL error contract](https://docs.rs/cpal/0.18.2/cpal/enum.ErrorKind.html). The inspected CoreAudio implementation emits DeviceChanged after its DefaultOutput unit reroutes and updates latency; processor-overload notifications produce Xrun.

The application defect was treating these notifications as fatal, stopping and destroying an otherwise usable output stream. It was not introduced by SQLite/library indexing. The OS reason for each default-output property notification is not established; AirPods were the selected output at the recorded device inventory. CoreAudio logs show Bluetooth startup messages and overloads around the original pre-merge failure (01:54:14) and baseline reproduction (01:58:40). Because the old callback discarded its event, the exact kind of those earlier individual failures cannot be recovered. The subsequent matching diagnostic failure definitively identifies DeviceChanged. An actual Xrun notice was also observed after the fix during the paused FLAC diagnostic session.

## Small fix

Rodio, CPAL, stream configuration and the Rust playback worker remain in place. The callback now hands off the actual CPAL error through per-stream bounded channels, with separate single pending slots for fatal errors and notices. It never waits for channel space or formats/logs messages in the callback. Notice bursts coalesce and cannot occupy the fatal-error slot. Retired streams cannot publish into a replacement stream's receiver.

DeviceChanged, Xrun and RealtimeDenied become visible output notices without changing playback state or rebuilding the stream. All other kinds, including unknown future kinds, remain fatal. The worker releases resources and retains a recoverable Error state with the real category/message and manual Play guidance. Default-device configuration and stream-initialization failures have separate stage prefixes. No automatic retries, telemetry, extra timers or permanent logging were added.

The existing copied snapshot JSON gains optional `output_notice`, decoded by Swift and shown in the existing message strip. The C scalar layout and functions are unchanged. Actual fatal errors take display precedence over notices. A new load clears old notices/errors. Formatting and UI work remain off the audio callback; existing rodio real-time limitations are unchanged.

## Verification

- 46 Rust tests and 13 Swift tests pass; cargo fmt, Clippy with warnings denied, native arm64 release build, C-header syntax, plist and signature checks pass.
- Test-first diagnostics/category tests cover preserved native detail (synthetic OSStatus detail), all three nonfatal kinds, notice floods versus fatal errors, and stale stream callbacks. A worker regression proves reroute notices retain Playing without resource teardown, paused device failure releases resources, valid reload clears the error/notice, and shutdown releases the recovered backend. Swift verifies notices decode independently of fatal errors and do not stop Playing refresh.
- Live engine example passes WAV/FLAC play, pause, resume, stop/reset, explicit restart, EOF, missing-file recovery and shutdown on the same default output. Configured output is still 48 kHz stereo F32.
- Native WAV play/pause/frozen position/resume/stop pass. Native FLAC play/pause/resume/stop/restart pass. A real DeviceChanged notice appears while FLAC remains Playing and its position advances: the former fatal event now leaves the stream active.
- Artist search works during FLAC playback. A 2,000-entry original-fixture import completes; a subsequent full 2,003-track rescan completes while FLAC remains Playing (position advances 0:00 to 0:01). No audio/library queue coupling was observed.
- Moving the isolated FLAC out of its saved path, stopping and explicitly replaying yields the expected missing-file error. Restoring it and pressing Play recovers. The fixture was restored.
- Process restart first restores the three pre-merge tracks and later all 2,003 indexed tracks without rescan; artist search still returns the tagged fixture. SQLite integrity_check returns ok, schema version 1.
- Native quit completes with exit code 0 after playback/database activity and after the persistence restart; the process exits. No user music or Application Support DB was used.

Final native executable is 2,740,656 bytes (+16,864 over the original v0.2 build). System SQLite linkage and historical spike documentation are preserved.

## Resource evidence and limits

One-shot ps/lsof checks observed 5 idle threads before engine creation, 11 while the WAV stream was paused, then 6 after Stop (the retained playback worker accounts for the additional idle thread). After repeated stop/restart cycles the stopped count remained 6. Audio file descriptors were 0 idle, 1 paused, 0 stopped and 0 after repeated cycles. Worker tests additionally count cleanup on fatal errors and shutdown. There is no observed accumulation of audio resources.

The system leaks tool has restricted access to the ad-hoc-signed release process and reports framework allocations: 452 objects/21,632 bytes after the v0.2 accessibility/picker session, versus 414 objects/19,888 bytes in an unchanged v0.1.1 session. Reported roots include AppKit NSAccessibilityCustomAction objects and system NSXPCConnection cycles; the larger session also has an NSXPCListenerEndpoint. These are not evidence that this patch leaks an audio stream, but they also prevent claiming a completely leak-free application. Full allocation attribution remains unverified; no OS protection or signing entitlement was weakened for profiling.

Audible listening/loopback, bit-perfect output, physical device-disconnection recovery and older macOS runtime compatibility remain unverified. The Rust standard-library macOS deployment warnings persist. Bluetooth scheduling glitches can still occur and are now visible rather than being mistaken for terminal playback failures. No further backend rewrite is justified by this investigation.

The reproduced playback blocker is resolved and the functional pre-merge checks pass. Merge readiness retains the documented hardware/OS/profiling limitations; no merge is performed by this task.
