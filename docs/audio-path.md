# Prototype audio path

Pinned rodio 0.23.0, Symphonia 0.5.5, cpal 0.18.2. Enabled rodio features: playback, flac, wav. Defaults (recording, other codecs and dithering) are disabled. Symphonia is also used directly for header probing; serde_json serves only copied bridge snapshots. No runtime network operations.

The worker creates and owns the decoder, Player and MixerDeviceSink. The default device config is used, and source properties are reported separately from configured output rate/channels/sample format. These are stream properties, not a measurement of the hardware's physical format. No volume processing is added by Reson.

## Callback audit

Inspected the pinned rodio sources stream.rs, player.rs, decoder/symphonia.rs, queue.rs and mixer.rs. The cpal callback advances rodio's mixer/source iterator. Symphonia's iterator reads packets and decodes them, allocating packet/sample buffers. Player and source queues contain mutex-protected controls. This can perform file reads, decoding, allocation and locking on the audio callback path. Consequently this prototype does **not** meet strict real-time callback guarantees. A future worker-decoded bounded PCM buffer would be needed before making that claim; it has not been implemented here. This is retained as a documented prototype limitation, in accordance with the instruction to use rodio initially.

Rodio uses floating samples and adapts rate/channels to the output stream. CoreAudio may additionally mix or convert. Lossless input does not establish bit-perfect output; 32-bit integer precision, rate-conversion transparency and exclusive hardware access are not verified. No gapless claim.

Startup is silent and lazy. Stop/EOF closes playback resources; pause retains the stream (which can continue rendering silence). Output callback errors set an atomic flag; the worker reports an error while playing. Errors occurring while paused are checked after resume. Corruption encountered after initial decoder construction may be treated as EOF/skipped packets by rodio rather than a detailed error; this is a dependency limitation.
