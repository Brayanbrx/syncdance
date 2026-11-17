"""A pitch track to the notes that were sung, and back.

A note is a run of frames that stays on one semitone:

- each frame takes the nearest semitone, but changing semitone has a cost
  (`semitone_path`), so a vibrato up to a semitone wide stays one note and a
  slide between two notes does not leave notes in between
- the whole recording may be tuned a little off A4 = 440 Hz: that global
  offset is removed before deciding the semitone, so a singer slightly flat
  all along does not flicker between two notes
- runs shorter than about 0.1 s are dropped (a pyin octave jump, a blip)
- a short gap (a consonant, a dropped blip) inside the same note is bridged

The pitch of each note is the center of its frames (`pitch_center`),
unrounded: the reference keeps how the instructor really sang it.
"""

import re
from dataclasses import dataclass

import numpy as np

from ai_engine.voice.pitch import HOP_MS, PitchTrack, frame_at

# Any change below changes the notes of every reference: bump the version.
ALGORITHM_VERSION = "voice-notes-v1"
SMOOTH_FRAMES = 7  # ~224 ms, for the global tuning only
# Semitones of distance a change of note must save. 2.0 keeps a vibrato up to
# ±80 cents at 4.5-5.5 Hz as one note and still finds 128 ms notes (synthetic
# tests; provisional until checked with real singers).
SWITCH_PENALTY = 2.0
MIN_NOTE_FRAMES = 3  # ~96 ms
MAX_GAP_FRAMES = 3  # ~96 ms

NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
_NOTE_PATTERN = re.compile(r"([A-Ga-g])(#|b)?(-?\d)")


def note_name(midi):
    """Nearest equal-tempered note, such as "F#3" (A4 = 440 Hz)."""
    number = int(np.floor(midi + 0.5))
    return f"{NOTE_NAMES[number % 12]}{number // 12 - 1}"


def parse_note(name):
    """MIDI number of a note name: A4 is 69, Bb3 is 58. ValueError otherwise."""
    match = _NOTE_PATTERN.fullmatch(str(name).strip())
    if not match:
        raise ValueError(f"not a note name: {name!r}")
    letter, accidental, octave = match.groups()
    number = NOTE_NAMES.index(letter.upper()) + (int(octave) + 1) * 12
    number += {"#": 1, "b": -1}.get(accidental or "", 0)
    if not 0 <= number <= 127:
        raise ValueError(f"note out of range: {name!r}")
    return number


@dataclass(frozen=True)
class Note:
    start_ms: int
    end_ms: int  # exclusive
    midi: float

    def __post_init__(self):
        if not (0 <= self.start_ms < self.end_ms):
            raise ValueError("a note needs 0 <= start_ms < end_ms")
        if not (np.isfinite(self.midi) and 0 <= self.midi <= 127):
            raise ValueError("a note needs a MIDI pitch between 0 and 127")

    @property
    def duration_ms(self):
        return self.end_ms - self.start_ms

    @property
    def name(self):
        return note_name(self.midi)

    def to_dict(self):
        return {
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
            "midi": round(float(self.midi), 2),
            "name": self.name,
        }


def tuning_offset(midi_values):
    """Global offset from equal temperament, in semitones within [-0.5, 0.5).

    A circular mean: a singer 45 cents sharp on some notes and 45 flat on
    others is near 0.5 either way, not near 0.
    """
    values = np.asarray(midi_values, dtype=float)
    values = values[np.isfinite(values)]
    if values.size == 0:
        return 0.0
    angles = 2 * np.pi * values
    offset = np.arctan2(np.sin(angles).mean(), np.cos(angles).mean()) / (2 * np.pi)
    return float(offset) if offset < 0.5 else float(offset - 1.0)


def pitch_center(values):
    """The pitch a run of frames is centered on: the mean without the 10 %
    highest and lowest. A vibrato swings evenly around its center, so its mean
    finds it; the median of a few sampled cycles can sit well off it."""
    values = np.sort(np.asarray(values, dtype=float)[np.isfinite(values)])
    if values.size == 0:
        return None
    cut = int(values.size * 0.1)
    return float(values[cut : values.size - cut].mean())


def rolling_median(midi, window):
    """Median of the voiced frames around each voiced frame; NaN elsewhere."""
    midi = np.asarray(midi, dtype=float)
    half = window // 2
    padded = np.pad(midi, half, constant_values=np.nan)
    windows = np.lib.stride_tricks.sliding_window_view(padded, 2 * half + 1)
    result = np.full(midi.size, np.nan)
    voiced = np.isfinite(midi)
    if voiced.any():
        result[voiced] = np.nanmedian(windows[voiced], axis=1)
    return result


def semitone_path(values, penalty=SWITCH_PENALTY):
    """The semitone each frame belongs to, changing note only when it pays.

    Viterbi over semitones: a frame costs its distance to the semitone, and
    every change of semitone costs `penalty`. A vibrato that swings a whole
    semitone away and back saves less than two changes, so it stays one note;
    a slide between two notes changes once, with no notes in between. Frames
    without voice cost nothing, so a short gap keeps its note.
    """
    values = np.asarray(values, dtype=float)
    voiced = np.isfinite(values)
    labels = np.full(values.size, np.nan)
    if not voiced.any():
        return labels
    states = np.arange(np.floor(values[voiced].min()) - 1, np.ceil(values[voiced].max()) + 2)
    cost = np.zeros((values.size, states.size))
    cost[voiced] = np.abs(values[voiced, None] - states[None, :])
    total = cost[0].copy()
    stayed = np.ones((values.size, states.size), dtype=bool)
    came_from = np.zeros(values.size, dtype=int)
    for index in range(1, values.size):
        best = int(total.argmin())
        switch = total[best] + penalty
        stayed[index] = total <= switch
        came_from[index] = best
        total = np.where(stayed[index], total, switch) + cost[index]
    state = int(total.argmin())
    for index in range(values.size - 1, -1, -1):
        labels[index] = states[state]
        if not stayed[index, state]:
            state = came_from[index]
    labels[~voiced] = np.nan
    return labels


def segment_notes(track):
    """The notes sung in a pitch track, in time order and never overlapping."""
    midi = track.midi
    voiced = np.isfinite(midi)
    if not voiced.any():
        return []
    # The global tuning comes from the smoothed pitch: a wide vibrato spreads
    # raw values over most of a semitone, and their circular mean can land on
    # the opposite side.
    offset = tuning_offset(rolling_median(midi, SMOOTH_FRAMES))
    labels = semitone_path(midi - offset)

    runs = []  # [label, start, end) in frames
    for index in np.flatnonzero(voiced):
        label = labels[index]
        if runs and runs[-1][0] == label and runs[-1][2] == index:
            runs[-1][2] = index + 1
        else:
            runs.append([label, index, index + 1])

    merged = []
    for run in (run for run in runs if run[2] - run[1] >= MIN_NOTE_FRAMES):
        if merged and merged[-1][0] == run[0] and run[1] - merged[-1][2] <= MAX_GAP_FRAMES:
            merged[-1][2] = run[2]
        else:
            merged.append(run)

    notes = []
    for label, start, end in merged:
        frames = midi[start:end][labels[start:end] == label]
        notes.append(
            Note(
                start_ms=int(start * track.hop_ms),
                end_ms=int(end * track.hop_ms),
                midi=round(pitch_center(frames), 2),
            )
        )
    return notes


def track_from_notes(notes, *, hop_ms=HOP_MS, duration_ms=None):
    """A pitch track that sings exactly these notes (exercises, tests)."""
    end = max((note.end_ms for note in notes), default=0)
    duration_ms = max(end, duration_ms or 0)
    midi = np.full(frame_at(duration_ms, hop_ms), np.nan)
    for note in notes:
        midi[frame_at(note.start_ms, hop_ms) : frame_at(note.end_ms, hop_ms)] = note.midi
    confidence = np.where(np.isfinite(midi), 1.0, 0.0)
    return PitchTrack(midi=midi, confidence=confidence, hop_ms=hop_ms)
