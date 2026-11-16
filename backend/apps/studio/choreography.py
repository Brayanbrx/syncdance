"""Tempo and steps an instructor marks on their routine.

The studio keeps a draft counted in beats (`Routine.choreography`), so the
steps survive a nudge of the first beat. Publishing freezes it into the
reference's `scoring_profile`, in milliseconds, which is what the phone reads:

- `beat_grid` (`beat-grid-v1`): the counts on screen and the dance game timing
- `steps` (`routine-steps-v1`): the list a student practises one by one

No Django imports: the rules are checked the same way by the API and tests.
"""

from ai_engine.choreography.curriculum import BEAT_GRID_VERSION, BEATS_PER_MOVE

STEPS_VERSION = "routine-steps-v1"
MIN_BPM, MAX_BPM = 60, 180  # the phone ignores a grid outside this range
MAX_STEPS = 40
MAX_COUNTS = 32  # four phrases of eight
NAME_LENGTH, TIP_LENGTH = 60, 140


class ChoreographyError(Exception):
    """A draft the studio refuses; the message is for the instructor."""

    def __init__(self, message, field="steps"):
        super().__init__(message)
        self.field = field


def beat_ms(bpm: float) -> float:
    return 60_000 / bpm


def clean(draft: dict, *, duration_ms: int) -> dict:
    """Check a draft from the editor against the video; return it with the
    steps in order. Without a tempo there is nothing to keep: {}."""
    bpm = draft.get("bpm")
    first = draft.get("first_beat_ms")
    steps = draft.get("steps") or []
    if bpm is None or first is None:
        if steps:
            raise ChoreographyError("Marca el tempo antes de los pasos.", field="bpm")
        return {}
    if not MIN_BPM <= bpm <= MAX_BPM:
        raise ChoreographyError(
            f"El tempo debe estar entre {MIN_BPM} y {MAX_BPM} BPM.", field="bpm"
        )
    if not 0 <= first < duration_ms:
        raise ChoreographyError(
            "El primer tiempo tiene que caer dentro del video.", field="first_beat_ms"
        )
    if len(steps) > MAX_STEPS:
        raise ChoreographyError(f"Hasta {MAX_STEPS} pasos por rutina.")
    beat = beat_ms(bpm)
    ordered = sorted(steps, key=lambda step: step["start_beat"])
    previous_end = None
    for number, step in enumerate(ordered, start=1):
        if not step["name"].strip():
            raise ChoreographyError(f"Ponle nombre al paso {number}.")
        if previous_end is not None and step["start_beat"] < previous_end:
            raise ChoreographyError(f"El paso {number} empieza antes de que termine el anterior.")
        previous_end = step["start_beat"] + step["counts"]
        if round(first + previous_end * beat) > duration_ms:
            raise ChoreographyError(f"El paso {number} termina después del final del video.")
    return {
        "bpm": round(float(bpm), 2),
        "first_beat_ms": int(first),
        "steps": [
            {
                "name": step["name"].strip()[:NAME_LENGTH],
                "start_beat": step["start_beat"],
                "counts": step["counts"],
                "tip": (step.get("tip") or "").strip()[:TIP_LENGTH],
            }
            for step in ordered
        ],
    }


def profile(draft: dict, *, duration_ms: int) -> dict:
    """The `scoring_profile` the phone receives; {} without a tempo."""
    if not draft or draft.get("bpm") is None:
        return {}
    bpm, first = draft["bpm"], draft["first_beat_ms"]
    beat = beat_ms(bpm)
    result = {
        "beat_grid": {
            "version": BEAT_GRID_VERSION,
            "bpm": bpm,
            "first_beat_ms": first,
            "beats_per_move": BEATS_PER_MOVE,
        }
    }
    if draft["steps"]:
        result["steps"] = {
            "version": STEPS_VERSION,
            "items": [
                {
                    "name": step["name"],
                    "start_ms": round(first + step["start_beat"] * beat),
                    "end_ms": min(
                        round(first + (step["start_beat"] + step["counts"]) * beat), duration_ms
                    ),
                    "counts": step["counts"],
                    "tip": step["tip"],
                }
                for step in draft["steps"]
            ],
        }
    return result
