"""Install the SyncDance singing exercises: guide audio + exact READY reference.

Rendering needs the voice extras (numpy, FFmpeg), so it runs in the backend or
worker image. Everything is original content: no license to verify.
"""

import hashlib
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.files.base import ContentFile
from django.db import transaction

from ai_engine.voice.audio import APP_AUDIO_PROFILE
from ai_engine.voice.exercises import EXERCISES, GENERATOR_VERSION, render_audio
from ai_engine.voice.reference import ALGORITHM_VERSION, exercise_reference

from .catalog import catalog_instructor
from .models import Routine, RoutineReference

LICENSE = "Contenido original de SyncDance (ejercicios y audio generados)"
POSITIONS = {exercise.key: index for index, exercise in enumerate(EXERCISES)}


def render(exercise, directory):
    """The guide audio (.m4a) bytes."""
    target = Path(directory) / "guide.m4a"
    render_audio(exercise, target)
    return target.read_bytes()


def catalog_key(exercise):
    return f"canto-{exercise.key}"


def _details(exercise, duration_ms):
    return {
        "name": exercise.name,
        "description": exercise.description,
        "difficulty": exercise.difficulty,
        "style": "Canto",
        "curriculum_position": POSITIONS[exercise.key],
        "generator": GENERATOR_VERSION,
        "license_name": LICENSE,
        "credit": "SyncDance",
        "duration_ms": duration_ms,
    }


def _publish(routine, version, built, audio_sha256, profile):
    reference = RoutineReference(
        routine=routine,
        version=version,
        status=RoutineReference.Status.READY,
        feature_schema="pitch-reference-v1",
        sample_rate_hz=31,
        engine_name=f"{built.metadata['engine']}-{GENERATOR_VERSION}",
        algorithm_version=ALGORITHM_VERSION,
        duration_ms=built.metadata["duration_ms"],
        checksum_sha256=built.sha256,
        source_video=routine.master_video.name,
        source_sha256=audio_sha256,
        playback_profile=APP_AUDIO_PROFILE,
        scoring_profile=profile,
    )
    reference.reference_asset.save(
        f"{routine.catalog_key}-v{version}.json.gz", ContentFile(built.payload), save=False
    )
    reference.full_clean()
    reference.save()
    return reference


def install(exercises=EXERCISES, *, renderer=render, only=None, refresh=False, log=print):
    """Create missing exercises. With `refresh`, render again and publish a new
    version only when the audio or the notes changed."""
    instructor = catalog_instructor()
    changed = 0
    for exercise in exercises:
        key = catalog_key(exercise)
        if only and exercise.key not in only and key not in only:
            continue
        routine = Routine.objects.filter(catalog_key=key).first()
        if routine and not refresh:
            log(f"= {key}: ya instalado")
            continue
        with TemporaryDirectory(prefix="syncdance-singing-") as directory:
            audio = renderer(exercise, directory)
        audio_sha256 = hashlib.sha256(audio).hexdigest()
        built = exercise_reference(
            exercise.notes(), duration_ms=exercise.duration_ms, source_sha256=audio_sha256
        )
        profile = {"beat_grid": exercise.beat_grid()}
        details = _details(exercise, built.metadata["duration_ms"])
        with transaction.atomic():
            if routine is None:
                routine = Routine.objects.create(
                    instructor=instructor,
                    kind=Routine.Kind.SING,
                    catalog_key=key,
                    master_video=ContentFile(audio, name=f"{key}.m4a"),
                    **details,
                )
                _publish(routine, 1, built, audio_sha256, profile)
                log(f"+ {key}: {exercise.name} ({details['duration_ms'] / 1000:.1f} s)")
            else:
                routine = Routine.objects.select_for_update().get(pk=routine.pk)
                latest = routine.references.filter(status=RoutineReference.Status.READY).first()
                if (
                    latest
                    and latest.checksum_sha256 == built.sha256
                    and latest.source_sha256 == audio_sha256
                    and latest.scoring_profile == profile
                ):
                    log(f"= {key}: sin cambios")
                    continue
                for field, value in details.items():
                    setattr(routine, field, value)
                routine.kind = Routine.Kind.SING
                routine.master_video.save(f"{key}.m4a", ContentFile(audio), save=False)
                routine.save()
                newest = routine.references.first()  # ordered by version, descending
                version = (newest.version if newest else 0) + 1
                _publish(routine, version, built, audio_sha256, profile)
                log(f"~ {key}: nueva versión v{version}")
        changed += 1
    return changed
