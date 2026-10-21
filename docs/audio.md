# Audio behaviour and limits

Reson supports local FLAC, PCM WAV and MP3 playback using rodio, Symphonia and cpal/CoreAudio. Exact dependency versions are recorded in `Cargo.lock`.

## Source and output

The audio-details popover reports the source format, sample rate, channels and known bit depth separately from the opened stream's rate, channels and sample format. Rodio mixes floating-point samples and adapts source rate/channels to the configured output. CoreAudio and the device can apply further conversion.

Lossless decoding does not imply bit-perfect output. Reson does not configure exclusive device access or OS-wide sample-rate matching. A matching reported rate does not establish physical output precision.

## Playback lifecycle

Output streams are opened lazily. Pause retains the stream and cursor; Stop and EOF release playback resources. Stop resets position. Play from Error follows the restart-from-beginning policy. Natural completion advances through Swift's queue/sequence coordinator.

Seeking applies to playing or paused tracks. Positions are clamped to valid source frames; nonfinite values are rejected. Replacement/Stop generations and seek sequences prevent stale operations from changing current playback. Volume and mute apply to the app, persist through macOS preferences and are restored for new streams. There is no ReplayGain, normalisation, EQ or custom gain ramp.

## Device selection and recovery

Each launch starts with System Default. An explicit device is pinned by ID for the session and never silently falls back when unavailable. Selection/retry closes the old stream, attempts the replacement and preserves position and playing/paused state when possible. Failed selection preserves the preference and cursor for recovery. Recovery from an output error through device selection leaves the source paused.

Device-change, xrun and scheduling notices are nonfatal when the stream remains valid. Fatal output errors release resources and require explicit recovery. Stream-scoped event channels keep retired callbacks from affecting replacement streams. Playing workers check events every 100 ms; paused streams every 500 ms. Empty/stopped/error workers block on commands. No periodic device enumeration runs while idle.

## Known limitations

- Automatic progression is not gapless: EOF reaches Swift before the next Load opens another stream. True gapless playback needs preprepared tracks and coordinated sample boundaries on a persistent stream.
- The inherited rodio/Symphonia callback path can read, decode, allocate and lock. It does not provide strict real-time guarantees.
- Corruption after initial decoder construction can appear as EOF or skipped packets rather than a detailed midstream decode error.
- Shutdown joins in-flight filesystem/device work and has no hard deadline.
- Automated command/state tests do not prove audible continuity, output precision or freedom from glitches. Listening and loopback measurements are separate checks.

See [testing](testing.md) for optional real-device checks and [performance](performance.md) for measurement guidance.

MP3 uses Symphonia’s MPEG Layer III decoder through the existing engine. It is lossy and has no source PCM bit depth; duration and seek precision depend on MP3 headers and encoder padding. AAC, ALAC, streams and other codecs remain unsupported. ID3v2.3/v2.4 APIC artwork is read lazily within fixed size limits; unsupported ID3 flags or image formats use the native placeholder.
