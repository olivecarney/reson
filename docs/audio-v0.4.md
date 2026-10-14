# Playback and audio in v0.4

Reson retains one Rust playback worker, one independent library worker, and Swift-owned sequence/history/queue coordination. SQLite remains schema 2. No dependencies or codecs were added.

## Seeking and timeline

Absolute seeks apply to Playing or Paused sources and carry the playback generation. Negative positions clamp to zero; positions beyond duration clamp to the last source frame. Nonfinite inputs are rejected. Targets round to the nearest source frame. Stop and Load advance the generation; shutdown is terminal. Successive queued seeks coalesce by accepted request sequence, and stale results cannot publish position or operation errors. Seek does not edit the queue or signal Ended. A playing source subsequently reaching its real end still advances normally.

The worker opens and seeks a replacement rodio decoder before retiring the existing player. Symphonia's accurate seek refines from its codec/container seek point to the requested PCM frame. A half-frame midpoint avoids nanosecond rounding below a frame boundary. WAV/FLAC reference-sample tests cover mono 44.1 kHz 16-bit and stereo 48 kHz 24-bit, including beginning and near-end positions. A failed preparation leaves the existing player/state intact and returns a recoverable `operation_error` through the C ABI. It does not become a fatal output error.

The stream stays open during a seek. A per-source atomic fence prevents a stopped player's decoder contributing further samples to its replacement while rodio's periodic stop control catches up. Device buffers already rendered cannot be retracted: a seek acknowledgement establishes decoder/cursor state, not when new samples emerge from the physical device. Reported playing position follows rodio's rendered-source cursor, polled at the existing 100 ms worker interval. UI snapshots normally refresh at 250 ms, briefly tighten to 100 ms in the last half-second or while awaiting a command, and return to 1 second while paused. Idle/stopped/errored presentation stops refreshing once acknowledged. Paused seek acknowledgements report the quantized target directly. Decoder creation and seek refinement run on the worker, rather than using Player::try_seek's callback feedback wait.

The native NSSlider supports click, drag, accessibility changes, five-second arrow-key steps and Home/End. It takes keyboard focus when clicked. Dragging owns a temporary position separate from engine snapshots and commits once at mouse-up. Replacement and Stop cancel that position. Unknown/zero duration and inactive sources disable the timeline. Native EOF sets the displayed position to full duration and clears retired output diagnostics.

## Gain and settings

Default gain is 1.0 (unity). Gain is bounded to 0…1, never changes macOS system volume, and uses rodio Player::set_volume without rebuilding the stream. Mute applies zero gain while retaining the slider value. A zero slider also presents an Unmute action, which restores positive gain in one click. Unmuting from a zero slider restores the previous positive gain (unity if none); setting a positive gain unmutes. New players inherit the effective gain across seek, track replacement and output changes.

Volume, mute and the previous positive gain persist through UserDefaults, outside SQLite. Preferences are installed when the bridge first creates its lazy engine, before any load, including an early Open File request. Invalid saved values are sanitized. After command backpressure, controls and saved preferences reconcile to acknowledged engine gain/mute rather than retaining a rejected optimistic value. Gain uses rodio's existing periodic control update; there is no custom ramp, EQ, ReplayGain, normalisation or other DSP. Audible click/ramp quality has not been measured.

## Outputs and recovery

The native output menu enumerates CPAL outputs once when the transport appears and on explicit Refresh Devices or opening audio details. It uses device IDs, with names only for display. There is no enumeration timer. The current choice has a checkmark in the menu, an accessible label/help text and a label in audio details. A disappeared preferred ID is shown as Unavailable output after refresh.

System Default uses CPAL's default-output device, which follows CoreAudio's valid automatic reroutes. Explicit devices come from enumeration and use CPAL's pinned HAL output path, including when the selected device happens to be the current system default. Explicit selection is session-only; every app launch starts with System Default. Gain preferences persist separately. Transport creation performs one asynchronous enumeration and starts a playback worker; output streams remain lazy. The worker blocks on commands when there is no active stream.

A deliberate selection/retry closes the previous stream before constructing a replacement. It freezes the source cursor, restores position, and preserves Playing/Paused state. Callback event channels belong to each stream and retired callbacks cannot affect its replacement. A build/disconnection failure stops resources, preserves the selected preference and cursor, and enters an output error. There is no silent fallback from an explicit selection. Reconnect and Retry Selected Output, or select another output/System Default. Recovery through selection returns an errored source paused; press Play when ready. Play from Error retains the existing restart-from-beginning policy. Stop drops resources and resets position.

DeviceChanged, Xrun and RealtimeDenied remain bounded, nonfatal notices. A completed automatic reroute does not rebuild a valid stream. Fatal notices halt automatic queue advancement. Physical unplug/default-route changes were not induced on the user's devices; deterministic event tests cover those paths and real unavailable-ID tests cover failed selection/recovery.

## Source versus output

The audio-details popover independently reports source format/rate/channels/known bit depth and actual opened stream rate/channels/sample format. A differing rate or channel count is explicitly identified as conversion. Stream configuration is cleared after Stop, Ended and fatal failure. The selected-track inspector remains independent of the playing-track transport and its artwork.

A matching rate does not establish bit-perfect output. Rodio mixes floating-point samples and adapts source rate/channels; CoreAudio/device conversion can also apply. No exclusive access, physical output precision or OS-wide rate matching is claimed or configured.

## Transitions and gapless

Automatic progression still travels from Rust's EOF snapshot through Swift's fenced completion consumer to the next Load. Play Next has priority; duplicate occurrences remain distinct. Stop, seeking, gain and output commands never impersonate EOF. The output stream is released at EOF/Stop; each new Load opens a stream.

Synthetic boundary fixtures contain nonzero DC markers in adjacent 44.1 kHz WAV/FLAC tracks, plus a 48 kHz differing-format track. Benchmarks mute their output. Worker EOF detection, next-load acknowledgement, decoder preparation, stream creation/destruction and Swift model start intervals are measured separately; see validation-v0.4.md. They demonstrate substantial stream/UI coordination overhead relative to decoder preparation. None measure DAC sample continuity.

True gapless playback is deferred. Reliable continuity would require preparing the next queue occurrence before EOF, keeping an output stream alive, and coordinating sample boundaries/queue ownership rather than awaiting UI-observed completion. This milestone avoids a second queue owner, speculative prebuffering or an engine rewrite. Ordinary automatic progression is not described as gapless. No listening or loopback capture was performed.

## Callback and compatibility limits

New control work, enumeration, probing, decoder seek preparation and diagnostic formatting happen off the audio callback. The source fence adds only an atomic read per sample. Inherited rodio/Symphonia iteration still reads files, decodes, allocates, locks and can release source/file resources through the callback. Strict realtime guarantees are not met. Corruption after initial construction may appear as EOF/skipped packets; detailed midstream decode-error reporting remains a dependency limitation. Shutdown joins outstanding file/device operations; no hard deadline is claimed.

The requested floor is macOS 14. Homebrew Rust's standard library on this machine emits macOS 27 linkage warnings; execution on macOS 14–26 remains unverified. No system output/rate settings are changed.
