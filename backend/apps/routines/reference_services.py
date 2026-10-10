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
    expired = queryset.filter(status="PROCESSING", processing_started_at__lt=limit).update(
        status="FAILED", processing_error="El proceso excedió su tiempo máximo."
    )
    expired += queryset.filter(status="PENDING", created_at__lt=limit).update(
        status="FAILED", processing_error="El trabajo no comenzó a tiempo. Genera otra versión."
    )
    if expired:
        logger.warning("Expired %s stale reference(s)", expired)
    return expired


def _dispatch(reference_id):
    from .tasks import generate_reference

    try:
        generate_reference.delay(reference_id)
    except Exception:
        logger.exception("Could not dispatch reference %s", reference_id)
        RoutineReference.objects.filter(pk=reference_id, status="PENDING").update(
            status="FAILED", processing_error="No se pudo enviar el trabajo. Genera otra versión."
        )


@transaction.atomic
def queue_reference(*, routine_id):
    # Serialize version allocation for this routine under PostgreSQL.
    routine = Routine.objects.select_for_update().get(pk=routine_id)
    if routine.generator:
        raise ValidationError(
            "Rutina generada desde su coreografía: se actualiza con generate_standard_catalog."
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
        feature_schema="motion-features-v1",
        sample_rate_hz=12,
    )
    transaction.on_commit(lambda: _dispatch(reference.pk))
    return reference
