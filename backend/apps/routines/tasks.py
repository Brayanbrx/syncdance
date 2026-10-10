import hashlib
import logging
from pathlib import Path
from tempfile import TemporaryDirectory

from celery import shared_task
from django.conf import settings
from django.core.files.base import ContentFile
from django.db import transaction
from django.utils import timezone

from ai_engine.pose.reference import MAX_SOURCE_BYTES, ReferenceError, build_reference

from .models import Routine, RoutineReference
from .reference_services import expire_stale_references as _expire_stale_references

logger = logging.getLogger(__name__)


@shared_task
def expire_stale_references():
    """Periodic (Celery Beat): recover references a crashed worker left running."""
    return _expire_stale_references()


@shared_task(soft_time_limit=1500, time_limit=1800)
def generate_reference(reference_id):
    # A duplicate Celery delivery never writes over a completed or running version.
    if not RoutineReference.objects.filter(pk=reference_id, status="PENDING").update(
        status="PROCESSING", processing_error="", processing_started_at=timezone.now()
    ):
        return
    reference = RoutineReference.objects.get(pk=reference_id)
    saved_asset = None
    try:
        if not reference.source_video:
            raise ReferenceError("La versión no tiene video maestro asociado.")
        with TemporaryDirectory(prefix="syncdance-source-") as workspace:
            local = Path(workspace) / "master.video"
            total = 0
            with reference.source_video.open("rb") as source, local.open("wb") as target:
                for chunk in source.chunks():
                    total += len(chunk)
                    if total > MAX_SOURCE_BYTES:
                        raise ReferenceError("El video supera el límite de 200 MB.")
                    target.write(chunk)
            payload, artifact = build_reference(
                local, model_path=settings.POSE_MODEL_PATH, sample_rate=reference.sample_rate_hz
            )
        checksum = hashlib.sha256(payload).hexdigest()
        reference.reference_asset.save(
            f"routine-{reference.routine_id}-v{reference.version}-{checksum[:12]}.json.gz",
            ContentFile(payload),
            save=False,
        )
        saved_asset = reference.reference_asset.name
        reference.checksum_sha256 = checksum
        reference.source_sha256 = artifact["source_sha256"]
        reference.engine_name = artifact["engine"]
        reference.algorithm_version = artifact["algorithm_version"]
        reference.duration_ms = artifact["duration_ms"]
        reference.status = "READY"
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
        logger.exception("Reference %s failed", reference_id)
        message = (
            str(exc) if isinstance(exc, ReferenceError) else "Falló el procesamiento del video."
        )
        RoutineReference.objects.filter(pk=reference_id, status="PROCESSING").update(
            status="FAILED", processing_error=message
        )
        if saved_asset:
            try:
                reference.reference_asset.storage.delete(saved_asset)
            except Exception:
                logger.exception("Could not remove orphan artifact for reference %s", reference_id)
