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


def _publish_reference(routine, version, payload, artifact, source_sha256, profile):
    reference = RoutineReference(
        routine=routine,
        version=version,
        status=RoutineReference.Status.READY,
        engine_name=artifact["engine"],
        algorithm_version=artifact["algorithm_version"],
        sample_rate_hz=artifact["sample_rate_hz"],
        duration_ms=artifact["duration_ms"],
        checksum_sha256=hashlib.sha256(payload).hexdigest(),
        source_video=routine.master_video.name,
        source_sha256=source_sha256,
        scoring_profile=profile,
    )
    reference.reference_asset.save(
        f"{routine.catalog_key}-v{version}.json.gz", ContentFile(payload), save=False
    )
    reference.full_clean()
    reference.save()
    return reference


def install(specs=STANDARD_V1, *, renderer=render, only=None, refresh=False, log=print):
    """Create missing routines. With `refresh`, re-render installed ones and
    publish a new reference version only when the result changed; earlier
    versions stay available, like any re-processed master."""
    instructor = catalog_instructor()
    changed = 0
    for spec in specs:
        key = catalog_key(spec)
        if only and spec.key not in only and key not in only:
            continue
        routine = Routine.objects.filter(catalog_key=key).first()
        if routine and not refresh:
            log(f"= {key}: ya instalada")
            continue
        with TemporaryDirectory(prefix="syncdance-standard-") as directory:
            video = renderer(spec, directory)
        source_sha256 = hashlib.sha256(video).hexdigest()
        payload, artifact = build_reference(spec, source_sha256=source_sha256)
        # The beat grid lets the dance game rate moves on the music.
        profile = {"beat_grid": spec.beat_grid()}
        details = {
            "name": spec.name,
            "description": spec.description,
            "difficulty": spec.difficulty,
            "style": spec.style,
            "generator": GENERATOR_VERSION,
            "license_name": LICENSE,
            "credit": f"SyncDance {CURRICULUM_VERSION}",
            "duration_ms": artifact["duration_ms"],
        }
        with transaction.atomic():
            if routine is None:
                routine = Routine.objects.create(
                    instructor=instructor,
                    catalog_key=key,
                    master_video=ContentFile(video, name=f"{key}.mp4"),
                    **details,
                )
                _publish_reference(routine, 1, payload, artifact, source_sha256, profile)
                log(f"+ {key}: {spec.name} ({artifact['duration_ms'] / 1000:.1f} s)")
            else:
                routine = Routine.objects.select_for_update().get(pk=routine.pk)
                latest = routine.references.filter(status=RoutineReference.Status.READY).first()
                if (
                    latest
                    and latest.checksum_sha256 == hashlib.sha256(payload).hexdigest()
                    and latest.scoring_profile == profile
                ):
                    log(f"= {key}: sin cambios")
                    continue
                for field, value in details.items():
                    setattr(routine, field, value)
                # A new file: the previous version keeps pointing at its own video.
                routine.master_video.save(f"{key}.mp4", ContentFile(video), save=False)
                routine.save()
                newest = routine.references.first()  # ordered by version, descending
                version = (newest.version if newest else 0) + 1
                _publish_reference(routine, version, payload, artifact, source_sha256, profile)
                log(f"~ {key}: nueva versión v{version}")
        changed += 1
    return changed
