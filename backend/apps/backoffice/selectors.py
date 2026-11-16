from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db.models import Count, OuterRef, Q, Subquery
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
        },
        "courses": {
            "courses": Course.objects.count(),
            "enrollments": Enrollment.objects.count(),
            "assignments": Assignment.objects.count(),
        },
        "latest_release": latest_release(),
    }
