from collections import defaultdict
from datetime import datetime, time, timedelta

from django.contrib.auth import get_user_model
from django.db.models import Count, OuterRef, Prefetch, Q, Subquery, Sum
from django.utils import timezone

from apps.coaching.models import Assignment, Course, Enrollment
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession

from .models import AppRelease


def latest_release():
    """The published build with the highest version code, or None."""
    return AppRelease.objects.filter(is_published=True).order_by("-version_code").first()


def panel_users(*, role=None, active=None, search=None):
    users = get_user_model().objects.order_by("-date_joined")
    if role:
        users = users.filter(role=role)
    if active is not None:
        users = users.filter(is_active=active)
    if search:
        users = users.filter(
            Q(username__icontains=search)
            | Q(email__icontains=search)
            | Q(first_name__icontains=search)
            | Q(last_name__icontains=search)
        )
    return users


def panel_routines():
    latest = RoutineReference.objects.filter(routine=OuterRef("pk")).order_by("-version")
    return (
        Routine.objects.select_related("instructor")
        .annotate(
            session_total=Count("dance_sessions", distinct=True),
            reference_status=Subquery(latest.values("status")[:1]),
            reference_version=Subquery(latest.values("version")[:1]),
        )
        .order_by("curriculum_position", "name")
    )


def catalog_proposals():
    """Routines instructors proposed for the catalog, oldest first."""
    return (
        Routine.objects.filter(catalog_review=Routine.CatalogReview.PENDING)
        .select_related("instructor")
        .prefetch_related(
            Prefetch("references", queryset=RoutineReference.objects.order_by("-version")),
            "published_in_courses",
        )
        .order_by("catalog_requested_at", "pk")
    )


def panel_courses():
    return (
        Course.objects.select_related("instructor")
        .annotate(
            student_total=Count("enrollments", distinct=True),
            assignment_total=Count("assignments", distinct=True),
        )
        .order_by("name")
    )


def platform_summary():
    """Counts for the panel home. Only aggregates: no names, no scores."""
    User = get_user_model()
    week_ago = timezone.now() - timedelta(days=7)
    roles = dict(User.objects.values_list("role").annotate(total=Count("id")))
    references = dict(RoutineReference.objects.values_list("status").annotate(total=Count("id")))
    sessions = DanceSession.objects.all()
    return {
        "users": {
            "students": roles.get(User.Role.STUDENT, 0),
            "instructors": roles.get(User.Role.INSTRUCTOR, 0),
            "admins": roles.get(User.Role.ADMIN, 0),
            "inactive": User.objects.filter(is_active=False).count(),
            "joined_last_7_days": User.objects.filter(date_joined__gte=week_ago).count(),
        },
        "practice": {
            "sessions": sessions.count(),
            "games": sessions.filter(game__isnull=False).count(),
            "sessions_last_7_days": sessions.filter(started_at__gte=week_ago).count(),
            "active_students_last_7_days": sessions.filter(started_at__gte=week_ago)
            .values("student")
            .distinct()
            .count(),
        },
        "catalog": {
            "routines": Routine.objects.count(),
            "active_routines": Routine.objects.filter(is_active=True).count(),
            "references_ready": references.get(RoutineReference.Status.READY, 0),
            "references_processing": references.get(RoutineReference.Status.PENDING, 0)
            + references.get(RoutineReference.Status.PROCESSING, 0),
            "references_failed": references.get(RoutineReference.Status.FAILED, 0),
            "proposals_pending": Routine.objects.filter(
                catalog_review=Routine.CatalogReview.PENDING
            ).count(),
        },
        "courses": {
            "courses": Course.objects.count(),
            "enrollments": Enrollment.objects.count(),
            "assignments": Assignment.objects.count(),
        },
        "latest_release": latest_release(),
    }


# --- pilot metrics (E5) -------------------------------------------------------

PILOT_WEEKS = 8
# Provisional gate of the pilot (docs: E5); the panel shows each against it.
PILOT_TARGETS = {
    "calibration": 0.8,
    "concordance": 0.6,
    "retention_week4": 0.4,
    "routines_per_instructor": 3,
}


def _week_start(moment):
    day = timezone.localtime(moment).date()
    return day - timedelta(days=day.weekday())


def pilot_metrics(*, now=None):
    """The pilot's gate figures, from synced practices only. Missing evidence
    is None (the panel shows "—"), never zero."""
    from apps.coaching.concordance import concordance

    now = now or timezone.now()
    completed = DanceSession.objects.filter(status=DanceSession.Status.COMPLETED)

    # Weekly activity: practices with evaluated time, Monday to Sunday (local).
    first_week = _week_start(now) - timedelta(weeks=PILOT_WEEKS - 1)
    weeks = {first_week + timedelta(weeks=i): (set(), 0) for i in range(PILOT_WEEKS)}
    since = timezone.make_aware(datetime.combine(first_week, time.min))
    for student, started in completed.filter(started_at__gte=since, evaluated_ms__gt=0).values_list(
        "student_id", "started_at"
    ):
        week = _week_start(started)
        if week in weeks:
            students, practices = weeks[week]
            students.add(student)
            weeks[week] = (students, practices + 1)

    # Week-4 retention: students whose first practice is at least 28 days old,
    # and who practised again between days 21 and 28 after it.
    days = defaultdict(list)
    for student, started in completed.order_by("started_at").values_list(
        "student_id", "started_at"
    ):
        days[student].append(started)
    cohort = [times for times in days.values() if times[0] <= now - timedelta(days=28)]
    retained = sum(
        any(times[0] + timedelta(days=21) <= t < times[0] + timedelta(days=28) for t in times)
        for times in cohort
    )

    # The account that owns the default catalog is not a pilot instructor.
    from apps.routines.catalog import CATALOG_USERNAME

    instructors = (
        get_user_model()
        .objects.filter(role=get_user_model().Role.INSTRUCTOR)
        .exclude(username=CATALOG_USERNAME)
        .annotate(
            published=Count(
                "routines",
                filter=Q(routines__published_at__isnull=False, routines__is_active=True),
                distinct=True,
            ),
            drafts=Count("routines", filter=Q(routines__published_at__isnull=True), distinct=True),
        )
        .order_by("username")
    )

    calibration = completed.aggregate(
        attempts=Sum("calibration_attempts"), calibrated=Sum("calibration_successes")
    )
    attempts = calibration["attempts"] or 0
    return {
        "weeks": [
            {"week_start": week, "active_students": len(students), "evaluated_practices": n}
            for week, (students, n) in sorted(weeks.items())
        ],
        "retention_week4": {
            "cohort": len(cohort),
            "retained": retained,
            "ratio": retained / len(cohort) if cohort else None,
        },
        "instructors": [
            {"username": i.username, "published": i.published, "drafts": i.drafts}
            for i in instructors
        ],
        "concordance": concordance(),
        "calibration": {
            "attempts": attempts,
            "calibrated": calibration["calibrated"] or 0,
            "ratio": (calibration["calibrated"] or 0) / attempts if attempts else None,
        },
        "targets": PILOT_TARGETS,
    }
