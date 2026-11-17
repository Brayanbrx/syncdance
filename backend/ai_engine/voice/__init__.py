"""Singing analysis that runs on the server, never in the live loop.

The live practice happens on the phone (Fase 9). The server only:

- turns the instructor's voice into a melody reference (`pitch-reference-v1`)
- optionally compares a student's recording with it, after the practice

Modules, from the file to the score:

- `audio`: any audio or video file to 16 kHz mono samples (FFmpeg)
- `pitch`: samples to a pitch track, one value every 32 ms (librosa pyin)
- `notes`: a pitch track to sung notes
- `reference`: the stored artifact, deterministic and versioned
- `evaluate`: scores against a reference, or of a voice alone

Adapted from the separate singing-service (v0.4.0). The grading was rewritten:
there it ranked a perfect scale at 24/100, hid wrong notes behind an unbounded
time warp and scored a song sung an octave lower at 0 %.

No Django imports. librosa and FFmpeg are imported lazily, on workers only.
"""

from ai_engine.pose.reference import ReferenceError


class VoiceError(ReferenceError):
    """A failure whose message is safe to show to the instructor or student."""
