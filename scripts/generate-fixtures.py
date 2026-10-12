#!/usr/bin/env python3
"""Original deterministic PCM fixtures; ffmpeg is only a development tool."""
import pathlib, subprocess, wave
root = pathlib.Path(__file__).resolve().parents[1] / 'tests/fixtures'
for bits, rate, channels in [(16,44100,1),(24,48000,2)]:
    name = f'pcm{bits}-{rate}-{channels}'
    width = bits // 8
    samples = [0, 1 << (bits-3), -(1 << (bits-3)), (1 << (bits-2))-1]
    data = b''.join(samples[i % 4].to_bytes(width, 'little', signed=True)
                    for i in range(rate // 10 * channels))
    path = root / (name + '.wav')
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(channels); f.setsampwidth(width); f.setframerate(rate); f.writeframes(data)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),str(root/(name+'.flac'))],check=True)
(root / 'malformed.wav').write_bytes(b'RIFF\x00\x00\x00\x00WAVEtruncated')
