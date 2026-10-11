"""Generate the dance game cues in assets/sfx/ (run from mobile/).

Original synthesized tones, standard library only and deterministic: running it
again rewrites identical files. Short and soft so they sit under the music.

    python tool/generate_sfx.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22_050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def tone(freq, ms, *, gain=0.45, glide_to=None):
    """Sine with a soft second harmonic, 5 ms attack and exponential decay."""
    count = round(RATE * ms / 1000)
    samples = []
    phase = 0.0
    for i in range(count):
        t = i / count
        f = freq if glide_to is None else freq + (glide_to - freq) * t
        phase += 2 * math.pi * f / RATE
        attack = min(1.0, i / (RATE * 0.005))
        envelope = attack * math.exp(-4.0 * t)
        value = math.sin(phase) + 0.25 * math.sin(2 * phase)
        samples.append(gain * envelope * value / 1.25)
    return samples


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(
            b"".join(struct.pack("<h", round(max(-1, min(1, s)) * 32767)) for s in samples)
        )


CUES = {
    # Countdown: a tick per number, a brighter tone when the song starts.
    "tick": tone(1000, 80),
    "go": tone(1500, 220),
    # Ratings, from a rising arpeggio (PERFECT) to a soft falling thud (MISS).
    "perfect": tone(1047, 70) + tone(1319, 70) + tone(1568, 140),
    "great": tone(1319, 70) + tone(1568, 130),
    "good": tone(784, 140, gain=0.35),
    "miss": tone(220, 180, gain=0.3, glide_to=150),
}

if __name__ == "__main__":
    for name, samples in CUES.items():
        write(name, samples)
        print(f"{name}.wav  {len(samples) * 1000 // RATE} ms")
