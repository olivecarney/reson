#!/usr/bin/env python3
"""Original v0.4 signals under an explicitly provided development directory."""
import pathlib, subprocess, sys, wave
root = pathlib.Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
for name, rate, channels, seconds, silent in [
    ('silent', 44100, 2, 8, True),
    ('boundary-a', 44100, 2, 0.2, False),
    ('boundary-b', 44100, 2, 0.2, False),
    ('boundary-48k', 48000, 2, 0.2, False),
]:
    frames = int(rate * seconds)
    # Nonzero DC boundary markers reveal inserted silence in a future capture.
    data = (0 if silent else 4096).to_bytes(2, 'little', signed=True) * frames * channels
    path = root / (name + '.wav')
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(channels); f.setsampwidth(2); f.setframerate(rate); f.writeframes(data)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(path), str(root/(name+'.flac'))], check=True)
