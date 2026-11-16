from datetime import timedelta

import pytest
from django.core.cache import cache
from django.utils import timezone

from apps.accounts.models import User
from apps.coaching.models import Assignment, Course, Enrollment
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession, GameResult


@pytest.fixture(autouse=True)
def fresh_throttle():
    # The course-code throttle counts in the cache and would leak between tests.
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def world(db):
    """Two instructors, each with a course and one student, and a routine
    assigned to the first course."""
    teacher = User.objects.create_user(
        username="profe", email="p@example.com", password="x", role="INSTRUCTOR"
    )
    other = User.objects.create_user(
        username="otra", email="o@example.com", password="x", role="INSTRUCTOR"
    )
    ana = User.objects.create_user(username="ana", email="a@example.com", password="x")
    luis = User.objects.create_user(username="luis", email="l@example.com", password="x")
    routine = Routine.objects.create(name="Paso básico", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        reference_asset="references/demo.json.gz",
        engine_name="fixture",
        checksum_sha256="a" * 64,
        algorithm_version="fixture-v1",
        duration_ms=10000,
    )
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    other_course = Course.objects.create(name="Danza 2B", instructor=other, join_code="WXYZ6789")
    Enrollment.objects.create(course=course, student=ana)
    Enrollment.objects.create(course=other_course, student=luis)
    assignment = Assignment.objects.create(
        course=course,
        routine=routine,
        target_stars=3,
        due_date=timezone.localdate() + timedelta(days=7),
    )

    def practice(student, *, points=None, speed=1.0):
        """A synced session; with [points] out of 400 it is a game."""
        now = timezone.now()
        session = DanceSession.objects.create(
            student=student,
            routine=routine,
            reference=reference,
            started_at=now,
            finished_at=now,
            status="COMPLETED",
            playback_speed=speed,
            reference_version=1,
        )
        if points is not None:
            GameResult.objects.create(
                session=session,
                version="dance-game-v2",
                points=points,
                max_points=400,
                max_combo=1,
                perfect=points // 100,
                great=0,
                good=0,
                miss=4 - points // 100,
                unrated=0,
            )
        return session

    return {
        "teacher": teacher,
        "other": other,
        "ana": ana,
        "luis": luis,
        "routine": routine,
        "course": course,
        "other_course": other_course,
        "assignment": assignment,
        "practice": practice,
    }
