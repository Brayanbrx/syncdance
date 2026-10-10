"""Exact motion-features-v1 reference from a choreography, without detection noise.

Landmarks go through the same feature extraction and encoder as MediaPipe
masters, so the phone validates and compares them like any other reference.
"""

from ai_engine.pose.reference import encode_reference

from .body import Camera
from .curriculum import GENERATOR_VERSION, spec_digest

SAMPLE_RATE = 12


def samples(timeline, camera=None):
    """12 Hz samples; the lead-in has no person, so it is never rated."""
    camera = camera or Camera()
    aspect = camera.width / camera.height
    count = round(timeline.duration_s * SAMPLE_RATE)
    for index in range(count):
        seconds = index / SAMPLE_RATE
        if timeline.evaluated_at(seconds):
            yield camera.landmarks(timeline.pose_at(seconds)), aspect, 1
        else:
            yield [], aspect, 0


def build_reference(spec, *, source_sha256, camera=None):
    return encode_reference(
        samples(spec.timeline(), camera),
        sample_rate=SAMPLE_RATE,
        engine=GENERATOR_VERSION,
        model_sha256=spec_digest(spec),
        source_sha256=source_sha256,
    )
