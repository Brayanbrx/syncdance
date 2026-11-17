"""Samples to a pitch track: which note sounds every 32 ms.

Pitch is kept as fractional MIDI numbers (60.0 is C4, 69.0 is A4 = 440 Hz), so
one cent is 0.01. A frame without voice is NaN in the arrays and `null` in any
JSON: never zero.
"""

import math
from dataclasses import dataclass

import numpy as np

from ai_engine.voice import VoiceError
from ai_engine.voice.audio import SAMPLE_RATE

# Any change below changes every pitch track: bump the version.
ALGORITHM_VERSION = "voice-pitch-v1"
HOP_LENGTH = 512  # 32 ms at 16 kHz
HOP_MS = HOP_LENGTH * 1000 // SAMPLE_RATE
FRAME_LENGTH = 2048
FMIN_HZ = 65.0  # C2: lower values turn silence into fake low notes
FMAX_HZ = 1600.0
# A frame this far below the loudest one is treated as silence even when pyin
# hears a pitch in it (room noise, a fan, the tail of a reverb).
SILENCE_DB = -40.0


def hz_to_midi(hz):
    return 69.0 + 12.0 * np.log2(np.asarray(hz, dtype=float) / 440.0)


def frame_at(ms, hop_ms):
    """First frame centered at or after `ms`: frames [frame_at(a), frame_at(b))
    are exactly those centered inside [a, b)."""
    return math.ceil(ms / hop_ms)


@dataclass(frozen=True, eq=False)
class PitchTrack:
    """One value per frame; frame `i` is centered at `i * hop_ms`."""

    midi: np.ndarray  # NaN where there is no voice
    confidence: np.ndarray  # pyin voicing probability, 0..1
    rms: np.ndarray | None = None  # signal level, for the volume score
    hop_ms: int = HOP_MS

    def __post_init__(self):
        if self.midi.ndim != 1 or self.confidence.shape != self.midi.shape:
            raise ValueError("pitch and confidence must be one value per frame")
        if self.rms is not None and self.rms.shape != self.midi.shape:
            raise ValueError("rms must be one value per frame")
        if self.hop_ms <= 0:
            raise ValueError("hop_ms must be positive")

    def __len__(self):
        return self.midi.size

    @property
    def voiced(self):
        return np.isfinite(self.midi)

    @property
    def duration_ms(self):
        return len(self) * self.hop_ms

    def frame(self, ms):
        """`frame_at` for this track (may fall outside it)."""
        return frame_at(ms, self.hop_ms)


def track_from_samples(samples):
    """Run pyin over 16 kHz mono samples."""
    samples = np.asarray(samples, dtype=np.float32)
    if samples.ndim != 1 or samples.size < FRAME_LENGTH:
        raise VoiceError("La grabación es demasiado corta.")
    try:
        import librosa
    except ImportError as exc:
        raise VoiceError("Faltan las dependencias de procesamiento de audio.") from exc

    f0, voiced_flag, voiced_prob = librosa.pyin(
        samples,
        fmin=FMIN_HZ,
        fmax=FMAX_HZ,
        sr=SAMPLE_RATE,
        frame_length=FRAME_LENGTH,
        hop_length=HOP_LENGTH,
    )
    rms = librosa.feature.rms(y=samples, frame_length=FRAME_LENGTH, hop_length=HOP_LENGTH)[0]
    size = min(f0.size, rms.size)
    f0 = f0[:size]
    voiced_flag = voiced_flag[:size]
    voiced_prob = voiced_prob[:size]
    rms = rms[:size].astype(float)

    loud = rms > 0
    if loud.any():
        floor = rms.max() * 10 ** (SILENCE_DB / 20)
        loud = rms > floor
    voiced = voiced_flag & np.isfinite(f0) & (f0 > 0) & loud
    midi = np.full(size, np.nan)
    midi[voiced] = hz_to_midi(f0[voiced])
    confidence = np.nan_to_num(voiced_prob, nan=0.0).clip(0.0, 1.0)
    return PitchTrack(midi=midi, confidence=confidence, rms=rms)
