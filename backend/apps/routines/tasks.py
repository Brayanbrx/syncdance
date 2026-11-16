import hashlib
import logging
from pathlib import Path
from tempfile import TemporaryDirectory

from celery import shared_task
from django.conf import settings
from django.core.files import File
from django.core.files.base import ContentFile
from django.db import transaction
from django.utils import timezone

from ai_engine.playback.app_video import PROFILE as APP_VIDEO_PROFILE
from ai_engine.playback.app_video import make_app_video, make_poster, poster_time_ms
from ai_engine.pose.reference import MAX_SOURCE_BYTES, ReferenceError, build_reference

from .models import Routine, RoutineReference
from .reference_services import expire_stale_references as _expire_stale_references

logger = logging.getLogger(__name__)


@shared_task
def expire_stale_references():
    """Periodic (Celery Beat): recover references a crashed worker left running."""
    return _expire_stale_references()


@shared_task(bind=True, soft_time_limit=1500, time_limit=1800)
def generate_reference(self, reference_id):
    task_id = self.request.id or ""
    log = {"reference_id": reference_id, "task_id": task_id}
    # A duplicate Celery delivery never writes over a completed or running version.
    started = {
        "status": "PROCESSING",
        "processing_error": "",
        "processing_started_at": timezone.now(),
    }
    if task_id:
        started["processing_task_id"] = task_id
    if not RoutineReference.objects.filter(pk=reference_id, status="PENDING").update(**started):
        logger.info("reference task skipped: not pending", extra=log)
        return
    logger.info("reference processing started", extra=log)
    reference = RoutineReference.objects.get(pk=reference_id)
    saved = []
    try:
        if not reference.source_video:
            raise ReferenceError("La versión no tiene video maestro asociado.")
        with TemporaryDirectory(prefix="syncdance-source-") as workspace:
            workspace = Path(workspace)
            local = workspace / "master.video"
            total = 0
            with reference.source_video.open("rb") as source, local.open("wb") as target:
                for chunk in source.chunks():
                    total += len(chunk)
                    if total > MAX_SOURCE_BYTES:
                        raise ReferenceError("El video supera el límite de 200 MB.")
                    target.write(chunk)
            # The reference comes from the file the phone plays, not the upload:
            # same first frame, same frame times (`video-start-cfr-v1`).
            app_video = workspace / "app.mp4"
            make_app_video(local, app_video, workspace=workspace)
            payload, artifact = build_reference(
                app_video, model_path=settings.POSE_MODEL_PATH, sample_rate=reference.sample_rate_hz
            )
            checksum = hashlib.sha256(payload).hexdigest()
            stem = f"routine-{reference.routine_id}-v{reference.version}-{checksum[:12]}"
            with app_video.open("rb") as video:
                reference.playback_video.save(f"{stem}.mp4", File(video), save=False)
            saved.append(reference.playback_video.name)
            reference.playback_profile = APP_VIDEO_PROFILE
            poster = workspace / "poster.jpg"
            try:
                make_poster(
                    app_video,
                    poster,
                    at_ms=poster_time_ms(artifact.get("frames"), artifact["duration_ms"]),
                )
                with poster.open("rb") as image:
                    reference.poster.save(f"{stem}.jpg", File(image), save=False)
                saved.append(reference.poster.name)
            except (ReferenceError, OSError):
                # A missing thumbnail never blocks a routine students can dance.
                logger.warning("reference poster not created", extra=log)
        reference.reference_asset.save(f"{stem}.json.gz", ContentFile(payload), save=False)
        saved.append(reference.reference_asset.name)
        reference.checksum_sha256 = checksum
        reference.source_sha256 = artifact["source_sha256"]
        reference.engine_name = artifact["engine"]
        reference.algorithm_version = artifact["algorithm_version"]
        reference.duration_ms = artifact["duration_ms"]
        reference.status = "READY"
        reference.processing_finished_at = timezone.now()
        reference.full_clean()
        with transaction.atomic():
            current = RoutineReference.objects.select_for_update().get(pk=reference_id)
            if current.status != "PROCESSING":
                raise ReferenceError("Esta ejecución ya no está vigente.")
            reference.save()
            # An older task must not change the duration of a replacement master.
            Routine.objects.filter(
                pk=reference.routine_id, master_video=reference.source_video.name
            ).update(duration_ms=reference.duration_ms)
    except Exception as exc:
        logger.exception("reference processing failed", extra=log)
        message = (
            str(exc) if isinstance(exc, ReferenceError) else "Falló el procesamiento del video."
        )
        RoutineReference.objects.filter(pk=reference_id, status="PROCESSING").update(
            status="FAILED", processing_error=message, processing_finished_at=timezone.now()
        )
        for name in saved:
            try:
                reference.reference_asset.storage.delete(name)
            except Exception:
                logger.exception("orphan reference file not removed", extra=log)
        return
    elapsed = reference.processing_finished_at - reference.processing_started_at
    logger.info(
        "reference ready",
        extra={
            **log,
            "version": reference.version,
            "engine": reference.engine_name,
            "duration_ms": reference.duration_ms,
            "elapsed_ms": round(elapsed.total_seconds() * 1000),
        },
    )
