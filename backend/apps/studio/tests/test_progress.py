"""Course progress for the instructor: difficulty map, practices and ratings."""

import uuid
from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.backoffice.selectors import pilot_metrics
from apps.coaching.concordance import spearman
from apps.coaching.models import Course, Enrollment, PracticeRating, SessionNote
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession, FeedbackCount, StepResult

pytestmark = pytest.mark.django_db

STEPS = [
    {"name": "Entrada", "start_ms": 0, "end_ms": 4000, "counts": 8, "tip": ""},
    {"name": "Giro", "start_ms": 4000, "end_ms": 6000, "counts": 4, "tip": ""},
]


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


@pytest.fixture
def course():
    teacher = User.objects.create_user(username="profe", email="p@e.com", role="INSTRUCTOR")
    other = User.objects.create_user(username="otra", email="o@e.com", role="INSTRUCTOR")
    course = Course.objects.create(name="Danza", instructor=teacher, join_code="ABCD2345")
    routine = Routine.objects.create(name="Salsa", instructor=teacher, difficulty="BEGINNER")
    course.published_routines.add(routine)
    reference = RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        reference_asset="references/salsa.json.gz",
        checksum_sha256="a" * 64,
        duration_ms=6000,
        scoring_profile={"steps": {"version": "routine-steps-v1", "items": STEPS}},
    )
    students = []
    for name in ("ana", "bea", "carla", "dani"):
        student = User.objects.create_user(username=name, email=f"{name}@e.com")
        Enrollment.objects.create(course=course, student=student)
        students.append(student)
    outsider = User.objects.create_user(username="zoe", email="z@e.com")
    return {
        "teacher": teacher,
        "other": other,
        "course": course,
        "routine": routine,
        "reference": reference,
        "students": students,
        "outsider": outsider,
    }


def practice(data, student, steps, *, days_ago=0, follow_mode="mirror", speed=1.0, cues=None):
    """A synced practice with per-step results: steps = [(evaluated_ms, score), ...]."""
    started = timezone.now() - timedelta(days=days_ago, minutes=len(steps))
    session = DanceSession.objects.create(
        id=uuid.uuid4(),
        student=student,
        routine=data["routine"],
        reference=data["reference"],
        started_at=started,
        finished_at=started + timedelta(seconds=6),
        status="COMPLETED",
        follow_mode=follow_mode,
        playback_speed=speed,
        pose_score=steps[0][1],
        overall_score=steps[0][1],
        duration_ms=6000,
        evaluated_ms=sum(e for e, _ in steps),
        quality_ratio=sum(e for e, _ in steps) / 6000,
        pose_schema_version="pose-v1",
        feature_schema_version="motion-features-v1",
        scoring_version="pose-window-v1",
        reference_version=1,
        step_summary_version="step-summary-v1",
    )
    for index, (evaluated, score) in enumerate(steps):
        StepResult.objects.create(
            session=session,
            index=index,
            start_ms=STEPS[index]["start_ms"],
            end_ms=STEPS[index]["end_ms"],
            evaluated_ms=evaluated,
            score=score if evaluated else None,
            feedback=(cues or {}).get(index, {}),
        )
    codes = {code for step in (cues or {}).values() for code in step}
    for code in codes:
        FeedbackCount.objects.create(
            session=session,
            code=code,
            region="left_arm",
            message="Sube el brazo izquierdo.",
            count=sum(step.get(code, 0) for step in cues.values()),
            max_severity=1.2,
        )
    return session


def map_of(data, **params):
    query = {"routine": data["routine"].pk, **params}
    return client_for(data["teacher"]).get(f"/api/studio/courses/{data['course'].pk}/map/", query)


def test_the_map_shows_each_student_latest_result_and_the_group(course):
    ana, bea, carla, dani = course["students"]
    practice(course, ana, [(4000, 40.0), (2000, 90.0)], days_ago=3)
    practice(course, ana, [(4000, 60.0), (500, 20.0)])  # step 2 barely seen: kept old
    practice(course, bea, [(3000, 45.0), (2000, 80.0)], cues={0: {"left_arm_up": 2}})
    practice(course, carla, [(4000, 30.0), (0, None)], cues={0: {"left_arm_up": 1}})
    practice(course, dani, [(4000, 99.0), (2000, 99.0)], speed=0.5)  # not comparable
    practice(course, course["outsider"], [(4000, 10.0), (2000, 10.0)])

    data = map_of(course).json()

    assert data["version"] == "difficulty-map-v1"
    assert data["reference_version"] == 1
    rows = {row["name"]: row["scores"] for row in data["students"]}
    assert rows == {
        "ana": [60.0, 90.0],
        "bea": [45.0, 80.0],
        "carla": [30.0, None],  # no evidence is "—", never 0
        "dani": [None, None],
    }
    first, second = data["steps"]
    assert (first["students"], first["median"], first["below_threshold"]) == (3, 45.0, 2 / 3)
    assert (second["students"], second["median"]) == (2, None)  # fewer than 3 students
    (error,) = first["frequent_errors"]
    assert (error["code"], error["students"], error["count"]) == ("left_arm_up", 2, 3)
    assert error["message"] == "Sube el brazo izquierdo."
    slow = map_of(course, speed="0.5").json()
    assert {row["name"]: row["scores"] for row in slow["students"]}["dani"] == [99.0, 99.0]
    assert slow["steps"][0]["median"] is None


def test_the_map_is_only_for_the_course_and_its_routines(course):
    other_routine = Routine.objects.create(
        name="Otra", instructor=course["other"], difficulty="BEGINNER"
    )
    assert map_of(course, routine=other_routine.pk).status_code == 404
    elsewhere = client_for(course["other"]).get(
        f"/api/studio/courses/{course['course'].pk}/map/", {"routine": course["routine"].pk}
    )
    assert elsewhere.status_code == 404
    detail = client_for(course["teacher"]).get(f"/api/studio/courses/{course['course'].pk}/")
    assert detail.json()["routines"] == [{"id": course["routine"].pk, "name": "Salsa", "steps": 2}]


def test_the_instructor_rates_practices_and_sees_the_concordance(course):
    client = client_for(course["teacher"])
    sessions = [
        practice(course, student, [(4000, score), (2000, score)])
        for student, score in zip(
            course["students"] * 2, [20, 35, 50, 65, 80, 95, 40, 70], strict=True
        )
    ]
    for session, stars in zip(sessions, [1, 2, 3, 3, 4, 5, 2, 4], strict=True):
        url = f"/api/studio/practices/{session.pk}/rating/"
        assert client.put(url, {"rating": stars}, format="json").status_code == 200

    commented = client.put(
        f"/api/studio/practices/{sessions[0].pk}/rating/",
        {"rating": 2, "comment": "Más amplitud en el giro."},
        format="json",
    )

    assert commented.status_code == 200
    assert PracticeRating.objects.get(session=sessions[0]).rating == 2
    assert SessionNote.objects.get().text == "Más amplitud en el giro."
    listed = client.get(f"/api/studio/courses/{course['course'].pk}/practices/").json()
    assert len(listed["practices"]) == 8
    assert {p["rating"] for p in listed["practices"]} == {2, 3, 4, 5}
    assert listed["concordance"]["pairs"] == 8
    assert listed["concordance"]["spearman"] > 0.9

    outsider = practice(course, course["outsider"], [(4000, 50.0), (2000, 50.0)])
    refused = client.put(f"/api/studio/practices/{outsider.pk}/rating/", {"rating": 3})
    assert refused.status_code == 404
    assert client.delete(f"/api/studio/practices/{sessions[1].pk}/rating/").status_code == 204
    assert not PracticeRating.objects.filter(session=sessions[1]).exists()


def test_spearman_needs_enough_pairs_and_spread():
    assert spearman([(1, 10), (2, 20), (3, 30), (4, 40), (5, 50)]) == pytest.approx(1)
    assert spearman([(5, 10), (4, 20), (3, 30), (2, 40), (1, 50)]) == pytest.approx(-1)
    assert spearman([(1, 10), (2, 20), (3, 30), (4, 40)]) is None
    assert spearman([(3, 10), (3, 20), (3, 30), (3, 40), (3, 50)]) is None
    tied = spearman([(1, 10), (1, 20), (2, 30), (3, 40), (3, 50)])
    assert 0.9 < tied < 1


def test_pilot_metrics(course):
    ana, bea, carla, _ = course["students"]
    practice(course, ana, [(4000, 50.0), (2000, 50.0)], days_ago=30)
    practice(course, ana, [(4000, 50.0), (2000, 50.0)], days_ago=5)  # day 25: retained
    practice(course, bea, [(4000, 50.0), (2000, 50.0)], days_ago=29)
    recent = practice(course, carla, [(4000, 50.0), (2000, 50.0)])
    recent.calibration_attempts, recent.calibration_successes = 5, 4
    recent.save()
    User.objects.create_user(username="catalogo", email="c@e.com", role="INSTRUCTOR")

    metrics = pilot_metrics()

    assert len(metrics["weeks"]) == 8
    assert metrics["weeks"][-1]["active_students"] >= 1
    assert metrics["retention_week4"] == {"cohort": 2, "retained": 1, "ratio": 0.5}
    assert metrics["calibration"] == {"attempts": 5, "calibrated": 4, "ratio": 0.8}
    assert {i["username"]: i["published"] for i in metrics["instructors"]} == {
        "otra": 0,
        "profe": 1,
    }
    assert metrics["concordance"] == {"pairs": 0, "spearman": None}
    response = client_for(course["teacher"]).get("/api/panel/pilot/")
    assert response.status_code == 403
