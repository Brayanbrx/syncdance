"""The instructor's melody, stored for the phone: `pitch-reference-v1`.

Like `motion-features-v1`: deterministic JSON (sorted keys, no NaN) gzipped
with mtime 0, so the same voice file and the same versions give the same bytes
and the same SHA-256. Frames are stored as columns to keep the file small.

The instructor uploads the voice alone. With music behind it, the tracker
follows the instruments; `quality.warnings` flags recordings that look like
that, so the studio can ask for a clean take.
"""

import gzip
import hashlib
import io
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ai_engine.voice import VoiceError, audio, pitch
from ai_engine.voice import notes as notes_module
from ai_engine.voice.notes import Note, segment_notes, track_from_notes, tuning_offset
from ai_engine.voice.pitch import PitchTrack

SCHEMA_VERSION = "pitch-reference-v1"
# What RoutineReference.algorithm_version records for a voice reference.
ALGORITHM_VERSION = f"{pitch.ALGORITHM_VERSION}+{notes_module.ALGORITHM_VERSION}"
MAX_COMPRESSED_BYTES = 4 * 1024 * 1024
MAX_EXPANDED_BYTES = 16 * 1024 * 1024
MIN_MELODY_MS = 1000
# Provisional, from synthetic tests: a clean voice leaves few loud frames
# without pitch, and pyin is sure of the pitch it finds.
ACTIVE_DB = -30.0
MAX_UNVOICED_ACTIVE = 0.5
MIN_CONFIDENCE = 0.5


@dataclass(frozen=True, eq=False)
class PitchReference:
    payload: bytes
    sha256: str
    track: PitchTrack
    notes: tuple
    metadata: dict  # the artifact without its frames


def voice_quality(track):
    """Signs that the recording is not a voice alone (music, noise)."""
    voiced = track.voiced
    quality = {
        "voiced_ratio": round(float(voiced.mean()), 3) if len(track) else 0.0,
        "median_confidence": (
            round(float(np.median(track.confidence[voiced])), 3) if voiced.any() else 0.0
        ),
        "unvoiced_active_ratio": None,
        "warnings": [],
    }
    if track.rms is not None and track.rms.size and track.rms.max() > 0:
        active = track.rms > track.rms.max() * 10 ** (ACTIVE_DB / 20)
        ratio = np.count_nonzero(active & ~voiced) / max(np.count_nonzero(active), 1)
        quality["unvoiced_active_ratio"] = round(float(ratio), 3)
    if (quality["unvoiced_active_ratio"] or 0) > MAX_UNVOICED_ACTIVE or (
        quality["median_confidence"] < MIN_CONFIDENCE
    ):
        quality["warnings"].append("NOT_VOICE_ONLY")
    return quality


def encode(track, sung, *, engine, engine_version, source_sha256, quality=None):
    """The artifact bytes for a track and its notes."""
    midi = [None if not np.isfinite(value) else round(float(value), 2) for value in track.midi]
    artifact = {
        "schema_version": SCHEMA_VERSION,
        "pitch_algorithm": pitch.ALGORITHM_VERSION,
        "notes_algorithm": notes_module.ALGORITHM_VERSION,
        "engine": engine,
        "engine_version": engine_version,
        "source_sha256": source_sha256,
        "sample_rate": audio.SAMPLE_RATE,
        "hop_ms": track.hop_ms,
        "duration_ms": track.duration_ms,
        "tuning_offset_cents": round(tuning_offset([note.midi for note in sung]) * 100),
        "frames": {
            "midi": midi,
            "confidence": [round(float(value), 2) for value in track.confidence],
        },
        "notes": [note.to_dict() for note in sung],
        "quality": quality or voice_quality(track),
    }
    payload = gzip.compress(
        json.dumps(artifact, sort_keys=True, separators=(",", ":"), allow_nan=False).encode(),
        mtime=0,
    )
    return decode(payload)


def decode(payload):
    """Check and read an artifact; raises VoiceError if anything is off."""
    if not isinstance(payload, bytes | bytearray) or len(payload) > MAX_COMPRESSED_BYTES:
        raise VoiceError("La referencia de voz no es válida.")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(payload)) as stream:
            raw = stream.read(MAX_EXPANDED_BYTES + 1)
        if len(raw) > MAX_EXPANDED_BYTES:
            raise ValueError("too large")
        artifact = json.loads(raw)
        track, sung = _read(artifact)
    except (OSError, EOFError, ValueError, TypeError, KeyError) as exc:
        raise VoiceError("La referencia de voz no es válida.") from exc
    metadata = {key: value for key, value in artifact.items() if key != "frames"}
    return PitchReference(
        payload=bytes(payload),
        sha256=hashlib.sha256(payload).hexdigest(),
        track=track,
        notes=tuple(sung),
        metadata=metadata,
    )


def _read(artifact):
    if artifact["schema_version"] != SCHEMA_VERSION:
        raise ValueError("unknown schema")
    for key in ("pitch_algorithm", "notes_algorithm", "engine", "source_sha256"):
        if not isinstance(artifact[key], str) or not artifact[key]:
            raise ValueError(f"missing {key}")
    hop_ms = artifact["hop_ms"]
    if type(hop_ms) is not int or hop_ms <= 0:
        raise ValueError("bad hop")
    midi = artifact["frames"]["midi"]
    confidence = artifact["frames"]["confidence"]
    if not isinstance(midi, list) or not isinstance(confidence, list):
        raise ValueError("frames must be lists")
    if len(midi) != len(confidence) or artifact["duration_ms"] != len(midi) * hop_ms:
        raise ValueError("frames do not match the duration")
    values = np.array([np.nan if value is None else value for value in midi], dtype=float)
    voiced = np.isfinite(values)
    if np.isinf(values).any() or (values[voiced] < 0).any() or (values[voiced] > 127).any():
        raise ValueError("pitch out of range")
    levels = np.array(confidence, dtype=float)
    if not np.all(np.isfinite(levels)) or (levels < 0).any() or (levels > 1).any():
        raise ValueError("confidence out of range")
    sung = []
    for item in artifact["notes"]:
        note = Note(int(item["start_ms"]), int(item["end_ms"]), float(item["midi"]))
        if (sung and note.start_ms < sung[-1].end_ms) or note.end_ms > artifact["duration_ms"]:
            raise ValueError("notes overlap or leave the track")
        sung.append(note)
    return PitchTrack(midi=values, confidence=levels, hop_ms=hop_ms), sung


def build_pitch_reference(source_path, *, max_seconds=audio.MAX_SECONDS):
    """The reference of the instructor's voice file."""
    path = Path(source_path)
    with path.open("rb") as source:
        source_hash = hashlib.file_digest(source, "sha256").hexdigest()
    track = pitch.track_from_samples(audio.decode(path, max_seconds=max_seconds))
    sung = segment_notes(track)
    if sum(note.duration_ms for note in sung) < MIN_MELODY_MS:
        raise VoiceError("No se encontró una voz cantando en la grabación.")
    import librosa

    return encode(
        track,
        sung,
        engine="librosa-pyin",
        engine_version=librosa.__version__,
        source_sha256=source_hash,
    )


def exercise_reference(sung, *, duration_ms=None, source_sha256=None):
    """A reference written as notes, for exercises (scales, held notes).

    `source_sha256` is the hash of the guide audio the phone plays, rendered
    from these same notes; without it, the hash of the note list.
    """
    if not sung:
        raise VoiceError("El ejercicio no tiene notas.")
    ordered = sorted(sung, key=lambda note: note.start_ms)
    for previous, note in zip(ordered, ordered[1:], strict=False):
        if note.start_ms < previous.end_ms:
            raise VoiceError("Las notas del ejercicio se superponen.")
    if source_sha256 is None:
        listing = json.dumps([note.to_dict() for note in ordered], sort_keys=True).encode()
        source_sha256 = hashlib.sha256(listing).hexdigest()
    return encode(
        track_from_notes(ordered, duration_ms=duration_ms),
        ordered,
        engine="notes",
        engine_version=notes_module.ALGORITHM_VERSION,
        source_sha256=source_sha256,
        quality={"voiced_ratio": None, "median_confidence": None, "warnings": []},
    )
