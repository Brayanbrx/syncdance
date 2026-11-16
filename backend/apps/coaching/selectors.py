from dataclasses import dataclass
from datetime import date, datetime

from django.contrib.auth import get_user_model
from django.db.models import Count, F, FloatField, Max, Prefetch, Q
from django.db.models.functions import Cast
from django.utils import timezone

from apps.training.models import DanceSession, GameResult

from .models import Assignment, Course, Enrollment, SessionNote


def students_of(*, user):
    """Students an account may review: everyone for superusers and the
    Administrator role, the students of their courses for an instructor."""
    users = get_user_model().objects.all()
    if user.manages_all_courses:
        return users
    if user.is_instructor:
        return users.filter(enrollments__course__instructor=user).distinct()
    return users.none()


def courses_managed_by(*, user):
    courses = Course.objects.select_related("instructor")
    if user.manages_all_courses:
        return courses
    if user.is_instructor:
        return courses.filter(instructor=user)
    return courses.none()


def _visible_routines():
    from apps.routines.models import Routine

    return Routine.objects.filter(is_active=True, published_at__isnull=False).order_by("name", "pk")


def visible_course_routines(course):
    """Routines published in the course that its students can dance now."""
    return list(_visible_routines().filter(published_in_courses=course))


def courses_for_student(*, user):
    return (
        Course.objects.filter(enrollments__student=user)
        .select_related("instructor")
        .prefetch_related(
            Prefetch("assignments", queryset=Assignment.objects.select_related("routine")),
            Prefetch(
                "published_routines",
                queryset=_visible_routines(),
                to_attr="visible_routines",
            ),
        )
        .annotate(joined_at=Max("enrollments__joined_at", filter=Q(enrollments__student=user)))
        .order_by("name", "pk")
    )


def notes_for_student(*, user):
    return SessionNote.objects.filter(session__student=user).select_related(
        "author", "session__routine"
    )


@dataclass(frozen=True)
class RoutineEvidence:
    """What the server knows of one student on one routine. Stars come from
    games at normal speed (learn mode is slower and does not meet a goal)."""

    best_stars: int | None
    practices: int
    last_practice_at: datetime | None


NO_EVIDENCE = RoutineEvidence(best_stars=None, practices=0, last_practice_at=None)


def routine_evidence(*, student_ids, routine_ids):
    """{(student_id, routine_id): RoutineEvidence} for the pairs with sessions."""
    rows = (
        DanceSession.objects.filter(student_id__in=student_ids, routine_id__in=routine_ids)
        .values("student_id", "routine_id")
        .annotate(
            practices=Count("id"),
            last_practice_at=Max("started_at"),
            best_ratio=Max(
                Cast("game__points", FloatField()) / F("game__max_points"),
                filter=Q(playback_speed=1.0, game__max_points__gt=0),
            ),
        )
    )
    return {
        (row["student_id"], row["routine_id"]): RoutineEvidence(
            best_stars=None
            if row["best_ratio"] is None
            else GameResult.stars_for(row["best_ratio"]),
            practices=row["practices"],
            last_practice_at=row["last_practice_at"],
        )
        for row in rows
    }


@dataclass(frozen=True)
class AssignmentStatus:
    evidence: RoutineEvidence
    completed: bool
    overdue: bool


def assignment_status(assignment, evidence, *, today: date | None = None):
    today = today or timezone.localdate()
    stars = evidence.best_stars
    completed = stars is not None and stars >= assignment.target_stars
    overdue = not completed and assignment.due_date is not None and assignment.due_date < today
    return AssignmentStatus(evidence=evidence, completed=completed, overdue=overdue)


def course_progress(*, course):
    """Rows per enrolled student with the status of every assignment, in the
    course's assignment order, for the instructor's review."""
    assignments = list(course.assignments.select_related("routine"))
    enrollments = list(Enrollment.objects.filter(course=course).select_related("student"))
    evidence = routine_evidence(
        student_ids=[e.student_id for e in enrollments],
        routine_ids=[a.routine_id for a in assignments],
    )
    today = timezone.localdate()
    rows = []
    for enrollment in enrollments:
        statuses = [
            assignment_status(
                a, evidence.get((enrollment.student_id, a.routine_id), NO_EVIDENCE), today=today
            )
            for a in assignments
        ]
        rows.append(
            {
                "student": enrollment.student,
                "joined_at": enrollment.joined_at,
                "statuses": statuses,
                "completed": sum(s.completed for s in statuses),
            }
        )
    return assignments, rows
