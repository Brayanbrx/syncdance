from django.db import IntegrityError, transaction
from rest_framework.exceptions import APIException

from .models import (
    DanceSession,
    ErrorEvent,
    FeedbackCount,
    GameResult,
    SegmentScore,
    StepResult,
    TimelineSegment,
)


class SessionAlreadyExists(APIException):
    status_code = 409
    default_detail = "El identificador de sesión ya existe. Consulta la sesión antes de reintentar."


def find_synced_session(*, student, session_id):
    """A retried upload of the same frozen summary is answered with the stored copy."""
    if session_id is None:
        return None
    return DanceSession.objects.filter(pk=session_id, student=student).first()


def create_session(
    *,
    student,
    segment_scores=(),
    timeline_segments=(),
    feedback_counts=(),
    error_events=(),
    game=None,
    step_results=(),
    calibration=None,
    **data,
):
    """Return (session, created). Summaries are immutable: a same-owner retry never rewrites."""
    reference = data["reference"]
    duration, evaluated = data.get("duration_ms"), data.get("evaluated_ms")
    if duration is not None:
        data["quality_ratio"] = evaluated / duration
    if calibration:
        data["calibration_attempts"] = calibration["attempts"]
        data["calibration_successes"] = calibration["calibrated"]
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
            TimelineSegment.objects.bulk_create(
                TimelineSegment(session=session, **segment) for segment in timeline_segments
            )
            FeedbackCount.objects.bulk_create(
                FeedbackCount(session=session, **item) for item in feedback_counts
            )
            ErrorEvent.objects.bulk_create(
                ErrorEvent(session=session, **event) for event in error_events
            )
            if game:
                GameResult.objects.create(session=session, **game)
            StepResult.objects.bulk_create(
                StepResult(session=session, **{"feedback": {}, **step}) for step in step_results
            )
    except IntegrityError:
        # A concurrent retry of the same upload may win the insert.
        existing = find_synced_session(student=student, session_id=data.get("id"))
        if existing:
            return existing, False
        if data.get("id") and DanceSession.objects.filter(pk=data["id"]).exists():
            raise SessionAlreadyExists() from None
        raise
    return session, True
