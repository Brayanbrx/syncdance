from django.db import IntegrityError, transaction
from rest_framework.exceptions import APIException

from .models import DanceSession, ErrorEvent, SegmentScore


class SessionAlreadyExists(APIException):
    status_code = 409
    default_detail = "El identificador de sesión ya existe. Consulta la sesión antes de reintentar."


def create_session(*, student, segment_scores=(), error_events=(), **data):
    reference = data["reference"]
    try:
        with transaction.atomic():
            session = DanceSession.objects.create(
                student=student,
                pose_schema_version=reference.pose_schema_version,
                feature_schema_version=reference.feature_schema,
                reference_version=reference.version,
                **data,
            )
            SegmentScore.objects.bulk_create(
                SegmentScore(session=session, **score) for score in segment_scores
            )
            ErrorEvent.objects.bulk_create(
                ErrorEvent(session=session, **event) for event in error_events
            )
    except IntegrityError:
        if data.get("id") and DanceSession.objects.filter(pk=data["id"]).exists():
            raise SessionAlreadyExists() from None
        raise
    return session
