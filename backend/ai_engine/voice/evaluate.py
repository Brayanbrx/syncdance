"""Scores of a sung recording: against a reference, or of a voice alone.

All thresholds and weights are provisional until checked with real singers and
teachers, like the dance ones; they travel with `SCORE_VERSION`.

Against a reference (`compare`), the faults of the old singing-service are
fixed on purpose:

- **Nothing is stretched.** The recording may start a little late or early:
  one global shift (up to ±1 s) is found from when the voice sounds and when
  it rests, never from the notes, then each reference note is judged where it
  was sung. A free time warp let a wrong note borrow the frames of a neighbor
  and pass as in tune.
- **An octave is not an error.** One octave shift for the whole recording is
  chosen (a man singing a woman's song). A semitone transposition is applied
  only when the caller says so (the student chose another key): guessing it
  would hide a singer who is a semitone flat all along.
- **Each note counts by its middle:** the center of the student's pitch over
  the central 60 % of the note, without the attack and the release.
- **Timing is relative to the track.** The recording is assumed to start with
  the backing track, as in the app. A note's entry is when the student
  reaches its pitch.
- **Absent is not zero.** A note not sung lowers the coverage, never the
  tuning; a score without evidence is None.

Alone (`evaluate_solo`), for warm-ups without a reference: each sung note
against the nearest semitone, once the singer's global tuning offset is
removed. A scale sung in tune scores high, whatever its notes.
"""

from dataclasses import dataclass, field

import numpy as np

from ai_engine.voice.notes import Note, note_name, pitch_center, segment_notes, tuning_offset
from ai_engine.voice.pitch import frame_at

SCORE_VERSION = "voice-score-v1"
CENT_THRESHOLD = 50  # against a reference
SOLO_CENT_THRESHOLD = 25  # alone: a note is never more than 50 cents from a semitone
MAX_OFFSET_MS = 1000
OCTAVE_MARGIN = 0.5  # another octave must at least halve the distance to the melody
EDGE_FRACTION = 0.2  # attack and release left out of each note
MIN_SUNG_FRACTION = 0.5  # of a note's middle, to count it as sung
MIN_STEADY_FRAMES = 10  # ~0.3 s: shorter notes say nothing about steadiness
STEADY_SMOOTH_FRAMES = 7  # removes a 5-7 Hz vibrato before measuring drift
ONSET_EARLY_MS = 400
ONSET_LATE_MS = 1000
ONSET_HOLD_FRAMES = 2  # the pitch must stay, not just pass by in a slide
ONSET_TOLERANCE_MS = 150
# The overall score starts from the tuning; timing, stability and volume can
# only take away up to EXTRA_SHARE of it. A steady, punctual wrong note is
# still a wrong note.
EXTRA_SHARE = 0.4
EXTRA_WEIGHTS = {"timing": 0.4, "stability": 0.3, "volume": 0.3}


@dataclass(frozen=True)
class Scores:
    """0-100, or None when there is no evidence for that part."""

    overall: int | None = None
    tuning: int | None = None
    timing: int | None = None
    stability: int | None = None
    volume: int | None = None
    coverage: int | None = None

    def to_dict(self):
        return dict(self.__dict__)


@dataclass(frozen=True)
class NoteResult:
    expected: Note
    sung_midi: float | None = None  # None: not sung
    cents: float | None = None
    in_tune: bool | None = None
    onset_error_ms: int | None = None  # None: not sung or cannot be timed
    steadiness_cents: float | None = None
    level_variation: float | None = None

    def to_dict(self):
        return {
            "expected": self.expected.to_dict(),
            "sung": None if self.sung_midi is None else note_name(self.sung_midi),
            "sung_midi": self.sung_midi,
            "cents": self.cents,
            "in_tune": self.in_tune,
            "onset_error_ms": self.onset_error_ms,
            "steadiness_cents": self.steadiness_cents,
            "level_variation": self.level_variation,
        }


@dataclass(frozen=True)
class Evaluation:
    mode: str  # "reference" or "solo"
    notes: tuple = ()
    scores: Scores = field(default_factory=Scores)
    offset_ms: int | None = None
    octave_shift: int = 0
    transpose_semitones: int = 0
    timing_bias_ms: int | None = None
    tuning_offset_cents: int | None = None

    def findings(self):
        """What to tell the singer, as stable codes; the app writes the words."""
        items = []
        if self.octave_shift:
            items.append({"code": "OCTAVE_SHIFT", "octaves": self.octave_shift})
        missed = sum(1 for note in self.notes if note.sung_midi is None)
        if missed:
            items.append({"code": "MISSED_NOTES", "count": missed})
        if self.timing_bias_ms is not None and abs(self.timing_bias_ms) >= ONSET_TOLERANCE_MS:
            code = "LATE" if self.timing_bias_ms > 0 else "EARLY"
            items.append({"code": code, "ms": abs(self.timing_bias_ms)})
        items.extend(
            {
                "code": "OUT_OF_TUNE",
                "start_ms": note.expected.start_ms,
                "expected": note.expected.name,
                "sung": note_name(note.sung_midi),
                "cents": note.cents,
            }
            for note in self.notes
            if note.in_tune is False
        )
        return items

    def to_dict(self):
        return {
            "version": SCORE_VERSION,
            "mode": self.mode,
            "scores": self.scores.to_dict(),
            "offset_ms": self.offset_ms,
            "octave_shift": self.octave_shift,
            "transpose_semitones": self.transpose_semitones,
            "timing_bias_ms": self.timing_bias_ms,
            "tuning_offset_cents": self.tuning_offset_cents,
            "notes": [note.to_dict() for note in self.notes],
            "findings": self.findings(),
        }


def compare(
    student,
    reference,
    notes,
    *,
    transpose_semitones=0,
    allow_octave=True,
    cent_threshold=CENT_THRESHOLD,
    max_offset_ms=MAX_OFFSET_MS,
):
    """Judge `student` against the reference track and its notes."""
    if student.hop_ms != reference.hop_ms:
        raise ValueError("both tracks need the same hop")
    if not notes:
        raise ValueError("the reference has no notes")
    hop = student.hop_ms
    sung = student.midi - transpose_semitones
    lag = best_lag(student.voiced, reference.voiced, max_frames=max_offset_ms // hop)

    middles, deviations = [], []
    for note in notes:
        start, end = _middle(frame_at(note.start_ms, hop) + lag, frame_at(note.end_ms, hop) + lag)
        values = _window(sung, start, end)
        voiced = values[np.isfinite(values)]
        enough = values.size > 0 and voiced.size >= MIN_SUNG_FRACTION * values.size
        middles.append((start, end))
        deviations.append(pitch_center(voiced) - note.midi if enough else None)

    octave = best_octave(deviations, notes) if allow_octave else 0
    shifted = sung - 12 * octave
    results = []
    for index, (note, deviation, (start, end)) in enumerate(
        zip(notes, deviations, middles, strict=True)
    ):
        if deviation is None:
            results.append(NoteResult(expected=note))
            continue
        cents = round(100 * (deviation - 12 * octave), 1)
        steadiness, level = _steadiness(student, start, end)
        results.append(
            NoteResult(
                expected=note,
                sung_midi=round(note.midi + deviation + transpose_semitones, 2),
                cents=cents,
                in_tune=abs(cents) <= cent_threshold,
                onset_error_ms=_onset_error(
                    shifted, note, notes[index - 1] if index else None, hop, cent_threshold
                ),
                steadiness_cents=steadiness,
                level_variation=level,
            )
        )

    timed = [note.onset_error_ms for note in results if note.onset_error_ms is not None]
    timing = _percent(sum(1 for error in timed if abs(error) <= ONSET_TOLERANCE_MS), len(timed))
    sung_ms = sum(note.expected.duration_ms for note in results if note.sung_midi is not None)
    coverage = _percent(sung_ms, sum(note.duration_ms for note in notes))
    parts = {
        "tuning": _tuning(results),
        "timing": timing,
        "stability": _stability(results),
        "volume": _volume(results),
    }
    return Evaluation(
        mode="reference",
        notes=tuple(results),
        scores=Scores(overall=_overall(parts, coverage), coverage=coverage, **parts),
        offset_ms=lag * hop,
        octave_shift=octave,
        transpose_semitones=transpose_semitones,
        timing_bias_ms=int(np.median(timed)) if timed else None,
    )


def evaluate_solo(track, *, cent_threshold=SOLO_CENT_THRESHOLD):
    """Judge a voice alone: intonation between its own notes."""
    sung = segment_notes(track)
    offset = tuning_offset([note.midi for note in sung])
    results = []
    for note in sung:
        target = float(np.floor(note.midi - offset + 0.5) + offset)
        cents = round(100 * (note.midi - target), 1)
        start, end = _middle(
            frame_at(note.start_ms, track.hop_ms), frame_at(note.end_ms, track.hop_ms)
        )
        steadiness, level = _steadiness(track, start, end)
        results.append(
            NoteResult(
                expected=Note(note.start_ms, note.end_ms, round(target, 2)),
                sung_midi=note.midi,
                cents=cents,
                in_tune=abs(cents) <= cent_threshold,
                steadiness_cents=steadiness,
                level_variation=level,
            )
        )
    parts = {
        "tuning": _tuning(results),
        "stability": _stability(results),
        "volume": _volume(results),
    }
    return Evaluation(
        mode="solo",
        notes=tuple(results),
        scores=Scores(overall=_overall(parts), **parts),
        tuning_offset_cents=round(offset * 100) if sung else None,
    )


def best_lag(student_voiced, reference_voiced, *, max_frames):
    """Shift, in frames, that best lines up when each one sings and breathes.

    Student frame `i` goes with reference frame `i - lag`, so a positive lag
    means the student is late. Ties go to the smallest shift. The pitch is
    left out on purpose: matching notes would let a scale sung in the wrong
    key slide by one note and look in tune.
    """
    best_key, best = None, 0
    for lag in range(-max_frames, max_frames + 1):
        student_from, reference_from = max(lag, 0), max(-lag, 0)
        size = min(student_voiced.size - student_from, reference_voiced.size - reference_from)
        if size <= 0:
            continue
        overlap = np.count_nonzero(
            student_voiced[student_from : student_from + size]
            & reference_voiced[reference_from : reference_from + size]
        )
        key = (int(overlap), -abs(lag), lag)
        if best_key is None or key > best_key:
            best_key, best = key, lag
    return best


def best_octave(deviations, notes):
    """One octave shift for the whole recording, in -2..2.

    Only a clear win moves away from 0: singing the same note all along is
    about as far from the melody one octave down as in place, and must not be
    reported as "you sang an octave lower".
    """
    pairs = [
        (deviation, note.duration_ms)
        for deviation, note in zip(deviations, notes, strict=True)
        if deviation is not None
    ]
    if not pairs:
        return 0

    def cost(octave):
        return sum(weight * abs(deviation - 12 * octave) for deviation, weight in pairs)

    best = min((-1, 1, -2, 2), key=lambda octave: (cost(octave), abs(octave)))
    return best if cost(best) <= OCTAVE_MARGIN * cost(0) else 0


def _window(values, start, end):
    """`values[start:end]`, with NaN where the range leaves the array."""
    out = np.full(max(end - start, 0), np.nan)
    low, high = max(start, 0), min(end, values.size)
    if high > low:
        out[low - start : high - start] = values[low:high]
    return out


def _middle(start, end):
    trim = int((end - start) * EDGE_FRACTION)
    return start + trim, end - trim


def _onset_error(shifted, note, previous, hop, cent_threshold):
    """When the student reached the note's pitch in tune, against the reference start.

    None for a note that repeats the previous pitch (the pitch alone cannot
    tell where one ends and the next begins) or that was never reached in
    tune: its tuning already counts, the timing has no evidence.
    """
    near = cent_threshold / 100
    if previous is not None:
        interval = abs(previous.midi - note.midi)
        if interval < 0.5:
            return None
        near = min(near, interval / 2)  # never mistake the previous note for this one
    first = frame_at(note.start_ms - ONSET_EARLY_MS, hop)
    values = _window(shifted, first, frame_at(note.start_ms + ONSET_LATE_MS, hop))
    with np.errstate(invalid="ignore"):
        close = np.abs(values - note.midi) <= near
    held = 0
    for index, ok in enumerate(close):
        held = held + 1 if ok else 0
        if held == ONSET_HOLD_FRAMES:
            return int((first + index - ONSET_HOLD_FRAMES + 1) * hop - note.start_ms)
    return None


def _steadiness(track, start, end):
    """Pitch drift in cents (vibrato removed) and level variation of a note."""
    values = _window(track.midi, start, end)
    voiced = np.isfinite(values)
    if np.count_nonzero(voiced) < MIN_STEADY_FRAMES:
        return None, None
    kernel = np.ones(STEADY_SMOOTH_FRAMES) / STEADY_SMOOTH_FRAMES
    drift = float(np.std(np.convolve(100 * values[voiced], kernel, mode="valid")))
    level = None
    if track.rms is not None:
        rms = _window(track.rms, start, end)[voiced]
        if np.all(np.isfinite(rms)) and rms.mean() > 0:
            level = round(float(rms.std() / rms.mean()), 3)
    return round(drift, 1), level


def _percent(part, whole):
    return None if whole <= 0 else round(100 * part / whole)


def _weighted_mean(pairs):
    pairs = [(value, weight) for value, weight in pairs if value is not None]
    total = sum(weight for _, weight in pairs)
    return None if total <= 0 else sum(value * weight for value, weight in pairs) / total


def _tuning(results):
    sung = [note for note in results if note.in_tune is not None]
    in_tune_ms = sum(note.expected.duration_ms for note in sung if note.in_tune)
    return _percent(in_tune_ms, sum(note.expected.duration_ms for note in sung))


def _stability(results):
    drift = _weighted_mean((note.steadiness_cents, note.expected.duration_ms) for note in results)
    return None if drift is None else int(np.clip(round(100 - 2 * drift), 0, 100))


def _volume(results):
    variation = _weighted_mean(
        (note.level_variation, note.expected.duration_ms) for note in results
    )
    return None if variation is None else int(np.clip(round(100 - 100 * variation), 0, 100))


def _overall(parts, coverage=None):
    """Tuning, less up to 40 % for the rest, times the share of notes sung."""
    if parts["tuning"] is None:
        return None
    extra = _weighted_mean((parts.get(name), weight) for name, weight in EXTRA_WEIGHTS.items())
    value = parts["tuning"]
    if extra is not None:  # no evidence takes nothing away
        value *= 1 - EXTRA_SHARE * (1 - extra / 100)
    if coverage is not None:
        value *= coverage / 100
    return round(value)
