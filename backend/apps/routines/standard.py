"""Install the generated SyncDance standard: coach video + exact READY reference.

Rendering needs the pose extras (numpy, OpenCV, FFmpeg), so it runs in the
backend/worker image. Everything is original content: no license to verify.
"""

import hashlib
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.files.base import ContentFile
from django.db import transaction

from ai_engine.choreography.curriculum import (
    CURRICULUM_VERSION,
    GENERATOR_VERSION,
    STANDARD_V1,
)
from ai_engine.choreography.reference import build_reference

from .catalog import catalog_instructor
from .models import Routine, RoutineReference

LICENSE = "Contenido original de SyncDance (coreografía y música generadas)"


def render(spec, directory):
    """Coach MP4 with its synthesized rhythm track; returns the video bytes."""
    from ai_engine.choreography.media import render_video, synth_audio

    timeline = spec.timeline()
    audio = Path(directory) / "beat.wav"
    video = Path(directory) / "coach.mp4"
    synth_audio(timeline, audio)
    render_video(timeline, video, audio_path=audio)
    return video.read_bytes()


def catalog_key(spec):
    return f"estandar-{spec.key}"


def install(specs=STANDARD_V1, *, renderer=render, only=None, log=print):
    """Create missing routines; existing keys are left untouched (idempotent)."""
    instructor = catalog_instructor()
    created = 0
    for spec in specs:
        key = catalog_key(spec)
        if only and spec.key not in only and key not in only:
            continue
        if Routine.objects.filter(catalog_key=key).exists():
            log(f"= {key}: ya instalada")
            continue
        with TemporaryDirectory(prefix="syncdance-standard-") as directory:
            video = renderer(spec, directory)
        source_sha256 = hashlib.sha256(video).hexdigest()
        payload, artifact = build_reference(spec, source_sha256=source_sha256)
        with transaction.atomic():
            routine = Routine.objects.create(
                instructor=instructor,
                name=spec.name,
                description=spec.description,
                difficulty=spec.difficulty,
                style=spec.style,
                catalog_key=key,
                generator=GENERATOR_VERSION,
                license_name=LICENSE,
                credit=f"SyncDance {CURRICULUM_VERSION}",
                master_video=ContentFile(video, name=f"{key}.mp4"),
                duration_ms=artifact["duration_ms"],
            )
            reference = RoutineReference(
                routine=routine,
                version=1,
                status=RoutineReference.Status.READY,
                engine_name=artifact["engine"],
                algorithm_version=artifact["algorithm_version"],
                sample_rate_hz=artifact["sample_rate_hz"],
                duration_ms=artifact["duration_ms"],
                checksum_sha256=hashlib.sha256(payload).hexdigest(),
                source_video=routine.master_video.name,
                source_sha256=source_sha256,
            )
            reference.reference_asset.save(f"{key}-v1.json.gz", ContentFile(payload), save=False)
            reference.full_clean()
            reference.save()
        created += 1
        log(f"+ {key}: {spec.name} ({artifact['duration_ms'] / 1000:.1f} s)")
    return created
