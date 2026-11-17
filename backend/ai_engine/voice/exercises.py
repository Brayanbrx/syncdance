"""SyncDance singing exercises: a guide audio and an exact reference.

Like the generated dance catalog, the reference comes from the notes, never
from analyzing the audio: the guide is rendered from the same notes, so both
agree to the millisecond. Everything is original content (scales, arpeggios
and a melody of our own): no license to check.

Each exercise starts with a bar of clicks (the count-in), then the guide sings
every note with a voice-like tone. The student may sing in any octave.
"""

import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ai_engine.voice.audio import make_app_audio
from ai_engine.voice.notes import Note, parse_note

GENERATOR_VERSION = "syncdance-voice-v1"
SAMPLE_RATE = 44100
COUNT_IN_BEATS = 4
GAP_MS = 60  # a breath between notes, so each one starts audibly
TAIL_MS = 800


@dataclass(frozen=True)
class Exercise:
    key: str
    name: str
    description: str
    difficulty: str
    bpm: int
    # (note name or None for a rest, length in beats)
    line: tuple

    @property
    def beat_ms(self):
        return 60000 / self.bpm

    def notes(self):
        """The sung notes, in ms from the start of the guide audio."""
        sung, beat = [], COUNT_IN_BEATS
        for name, beats in self.line:
            if name is not None:
                start = round(beat * self.beat_ms)
                end = round((beat + beats) * self.beat_ms) - GAP_MS
                sung.append(Note(start, end, float(parse_note(name))))
            beat += beats
        return sung

    @property
    def duration_ms(self):
        beats = COUNT_IN_BEATS + sum(beats for _, beats in self.line)
        return round(beats * self.beat_ms) + TAIL_MS

    def beat_grid(self):
        """Same shape as the dance `beat-grid-v1`: the app can show the count."""
        return {
            "version": "beat-grid-v1",
            "bpm": self.bpm,
            "first_beat_ms": 0,
            "beats_per_bar": 4,
        }


EXERCISES = (
    Exercise(
        "v1-nota-larga",
        "Notas largas",
        "Sostén cada nota los cuatro tiempos sin que suba ni baje. Respira en los silencios.",
        "BEGINNER",
        72,
        (("C4", 4), (None, 2), ("D4", 4), (None, 2), ("E4", 4), (None, 2), ("C4", 4)),
    ),
    Exercise(
        "v1-cinco-notas",
        "Escalera de cinco notas",
        "Sube paso a paso de Do a Sol y vuelve a bajar. Cada nota dura un tiempo.",
        "BEGINNER",
        84,
        (
            ("C4", 1),
            ("D4", 1),
            ("E4", 1),
            ("F4", 1),
            ("G4", 1),
            ("F4", 1),
            ("E4", 1),
            ("D4", 1),
            ("C4", 4),
        ),
    ),
    Exercise(
        "v1-arpegio",
        "Arpegio de Do",
        "Salta por las notas del acorde: Do, Mi, Sol y el Do de arriba, y regresa.",
        "BEGINNER",
        76,
        (
            ("C4", 1),
            ("E4", 1),
            ("G4", 1),
            ("C5", 2),
            ("G4", 1),
            ("E4", 1),
            ("C4", 3),
        ),
    ),
    Exercise(
        "v1-terceras",
        "Saltos de tercera",
        "Alterna una nota y la que está dos más arriba. Escucha cada salto antes de cantarlo.",
        "INTERMEDIATE",
        80,
        (
            ("C4", 1),
            ("E4", 1),
            ("D4", 1),
            ("F4", 1),
            ("E4", 1),
            ("G4", 1),
            ("F4", 1),
            ("A4", 1),
            ("G4", 4),
        ),
    ),
    Exercise(
        "v1-escala",
        "Escala completa",
        "La escala de Do de punta a punta, subiendo y bajando sin cortar el aire.",
        "INTERMEDIATE",
        92,
        (
            ("C4", 1),
            ("D4", 1),
            ("E4", 1),
            ("F4", 1),
            ("G4", 1),
            ("A4", 1),
            ("B4", 1),
            ("C5", 2),
            ("B4", 1),
            ("A4", 1),
            ("G4", 1),
            ("F4", 1),
            ("E4", 1),
            ("D4", 1),
            ("C4", 3),
        ),
    ),
    Exercise(
        "v1-melodia",
        "Melodía del faro",
        "Una melodía corta de SyncDance con saltos y notas largas. Mantén el tempo.",
        "ADVANCED",
        88,
        (
            ("E4", 1),
            ("G4", 1),
            ("A4", 2),
            ("G4", 1),
            ("E4", 1),
            ("D4", 2),
            (None, 1),
            ("C4", 1),
            ("D4", 1),
            ("E4", 1),
            ("G4", 2),
            ("E4", 1),
            ("D4", 1),
            ("C4", 4),
        ),
    ),
)


def _tone(midi, samples):
    """A soft voice-like tone: harmonics, light vibrato, gentle attack."""
    t = np.arange(samples) / SAMPLE_RATE
    hz = 440.0 * 2 ** ((midi - 69) / 12)
    vibrato = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.4)
    phase = 2 * np.pi * np.cumsum(hz * vibrato) / SAMPLE_RATE
    wave_ = sum(a * np.sin(k * phase) for k, a in ((1, 1.0), (2, 0.45), (3, 0.2), (4, 0.08)))
    attack = np.minimum(1, t / 0.04)
    release = np.minimum(1, (t[-1] - t) / 0.06) if samples else t
    return 0.22 * wave_ * attack * release


def _click(accent):
    """A short wooden tick with no pitch: a microphone that hears it must not
    take it for a sung note."""
    samples = int(0.03 * SAMPLE_RATE)
    t = np.arange(samples) / SAMPLE_RATE
    noise = np.random.default_rng(7).uniform(-1, 1, samples)  # fixed: same file every time
    return (0.45 if accent else 0.3) * noise * np.exp(-t / 0.006)


def render_samples(exercise):
    """The guide as float samples at `SAMPLE_RATE`, deterministic."""
    total = int(exercise.duration_ms * SAMPLE_RATE / 1000)
    out = np.zeros(total)
    for beat in range(COUNT_IN_BEATS):
        start = int(beat * exercise.beat_ms * SAMPLE_RATE / 1000)
        click = _click(beat == 0)
        out[start : start + click.size] += click
    for note in exercise.notes():
        start = int(note.start_ms * SAMPLE_RATE / 1000)
        end = int(note.end_ms * SAMPLE_RATE / 1000)
        out[start:end] += _tone(note.midi, end - start)
    return np.clip(out, -1, 1)


def render_audio(exercise, target):
    """The guide as the phone plays it (`app-audio-v1`, .m4a)."""
    with tempfile.TemporaryDirectory(prefix="syncdance-voice-") as workspace:
        wav = Path(workspace) / "guide.wav"
        pcm = (render_samples(exercise) * 32767).astype("<i2")
        with wave.open(str(wav), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(SAMPLE_RATE)
            out.writeframes(pcm.tobytes())
        make_app_audio(wav, target)
