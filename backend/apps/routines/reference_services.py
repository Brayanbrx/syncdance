import logging
from datetime import timedelta

from django.db import transaction
from django.db.models import Max
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from .models import Routine, RoutineReference

logger = logging.getLogger(__name__)

# Past the task hard time limit (30 min) a reference can no longer be running.
STALE_AFTER = timedelta(minutes=31)


def expire_stale_references(*, routine=None):
    """Mark references a lost worker left PENDING/PROCESSING as FAILED.

    Conditional UPDATEs: safe to repeat and to run beside a finishing task,
    which re-checks its status under a row lock before publishing.
    """
    queryset = routine.references.all() if routine else RoutineReference.objects.all()
    limit = timezone.now() - STALE_AFTER
    now = timezone.now()
    expired = queryset.filter(status="PROCESSING", processing_started_at__lt=limit).update(
        status="FAILED",
        processing_error="El proceso excedió su tiempo máximo.",
        processing_finished_at=now,
    )
    expired += queryset.filter(status="PENDING", created_at__lt=limit).update(
        status="FAILED",
        processing_error="El trabajo no comenzó a tiempo. Genera otra versión.",
        processing_finished_at=now,
    )
    if expired:
        logger.warning("stale references expired", extra={"expired": expired})
    return expired


def reference_schema(routine) -> dict:
    """What a new version of this routine holds: body pose or melody."""
    if routine.is_singing:
        # One pitch value every 32 ms (31.25 per second, stored rounded).
        return {"feature_schema": "pitch-reference-v1", "sample_rate_hz": 31}
    return {"feature_schema": "motion-features-v1", "sample_rate_hz": 12}


def _dispatch(reference_id):
    from .tasks import generate_reference

    try:
        result = generate_reference.delay(reference_id)
    except Exception:
        logger.exception("reference dispatch failed", extra={"reference_id": reference_id})
        RoutineReference.objects.filter(pk=reference_id, status="PENDING").update(
            status="FAILED",
            processing_error="No se pudo enviar el trabajo. Genera otra versión.",
            processing_finished_at=timezone.now(),
        )
        return
    task_id = getattr(result, "id", None)
    if isinstance(task_id, str) and task_id:
        # An eager run (tests) already stored it: never overwrite.
        RoutineReference.objects.filter(pk=reference_id, processing_task_id="").update(
            processing_task_id=task_id
        )
    logger.info("reference queued", extra={"reference_id": reference_id, "task_id": task_id})


@transaction.atomic
def queue_reference(*, routine_id):
    # Serialize version allocation for this routine under PostgreSQL.
    routine = Routine.objects.select_for_update().get(pk=routine_id)
    if routine.generator:
        command = "generate_singing_catalog" if routine.is_singing else "generate_standard_catalog"
        raise ValidationError(
            f"Rutina generada desde sus notas o coreografía: se actualiza con {command}."
        )
    if not routine.master_video:
        raise ValidationError("La rutina requiere un video maestro.")
    expire_stale_references(routine=routine)
    pending = routine.references.filter(
        source_video=routine.master_video.name, status__in=["PENDING", "PROCESSING"]
    ).first()
    if pending:
        return pending
    version = (routine.references.aggregate(value=Max("version"))["value"] or 0) + 1
    reference = RoutineReference.objects.create(
        routine=routine,
        version=version,
        source_video=routine.master_video.name,
        **reference_schema(routine),
    )
    transaction.on_commit(lambda: _dispatch(reference.pk))
    return reference
