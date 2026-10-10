from django.db.models import Count, F, FloatField, Max, Q
from django.db.models.functions import Cast

from .models import DanceSession, GameResult

# Same provisional floor as the phone's routine progress (routine-progress-v2).
MIN_PROGRESS_COVERAGE = 0.5


def get_sessions_for_user(*, user):
    # Instructor/student sharing belongs to a later phase; sessions are private.
    return (
        DanceSession.objects.filter(student=user)
        .select_related("routine", "reference", "game")
        .prefetch_related("segment_scores", "timeline_segments", "feedback_counts", "error_events")
    )


def get_student_progress():
    """Per student and routine, for the instructor: practices, games, best
    similarity at normal speed with enough coverage, best game stars and the
    last practice. Missing evidence stays None, never zero."""
    rows = (
        DanceSession.objects.values("student__username", "routine__name")
        .annotate(
            practices=Count("id"),
            games=Count("game"),
            best_score=Max(
                "pose_score",
                filter=Q(playback_speed=1.0, quality_ratio__gte=MIN_PROGRESS_COVERAGE),
            ),
            best_game_ratio=Max(
                Cast("game__points", FloatField()) / F("game__max_points"),
                filter=Q(game__max_points__gt=0),
            ),
            last_practice=Max("started_at"),
        )
        .order_by("student__username", "routine__name")
    )
    return [
        {
            **row,
            "best_stars": None
            if row["best_game_ratio"] is None
            else GameResult.stars_for(row["best_game_ratio"]),
        }
        for row in rows
    ]
