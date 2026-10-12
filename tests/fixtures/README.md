# Original fixtures

Run `python3 scripts/generate-fixtures.py` with Python 3 and ffmpeg on PATH.
Four files cover 16-bit mono 44.1 kHz and 24-bit stereo 48 kHz, each as PCM WAV and FLAC, lasting 0.1 s. Each interleaved sample repeats 0, 1/4, -1/4, 1/2 minus one integer quantization step. These are original synthetic test data, not music copied from another source. malformed.wav is intentionally truncated.

A fifth valid file, tagged.wav, adds RIFF title/artist tags with container NUL padding to verify clean UI text.
