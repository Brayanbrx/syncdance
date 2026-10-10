from .models import DanceSession


def get_sessions_for_user(*, user):
    # Instructor/student sharing belongs to a later phase; sessions are private.
    return (
        DanceSession.objects.filter(student=user)
        .select_related("routine", "reference")
        .prefetch_related("segment_scores", "timeline_segments", "feedback_counts", "error_events")
    )
