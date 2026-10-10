import uuid

import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession

pytestmark = pytest.mark.django_db


@pytest.fixture
def setup_session():
    teacher = User.objects.create_user(username="teacher", email="t@example.com", role="INSTRUCTOR")
    student = User.objects.create_user(username="student", email="s@example.com")
    routine = Routine.objects.create(name="Demo", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference.objects.create(
        routine=routine,
        version=2,
        status="READY",
        reference_asset="references/demo.json.gz",
        engine_name="fixture",
        checksum_sha256="a" * 64,
        algorithm_version="fixture-v1",
        duration_ms=30000,
    )
    client = APIClient()
    client.force_authenticate(student)
    payload = {
        "id": str(uuid.uuid4()),
        "routine": routine.pk,
        "reference": reference.pk,
        "started_at": "2026-10-01T12:00:00Z",
        "finished_at": "2026-10-01T12:00:30Z",
        "status": "COMPLETED",
        "scoring_version": "fixture-score-v1",
        "pose_score": 80,
        "timing_score": None,
        "quality_ratio": 0.75,
        "segment_scores": [{"segment": "ARMS", "score": 80, "coverage": 0.75}],
        "error_events": [
            {
                "code": "arm_low",
                "body_part": "ARMS",
                "joint": "leftElbow",
                "start_ms": 1000,
                "end_ms": 1200,
                "severity": "LOW",
                "magnitude": 12,
                "feedback_key": "raise_arm",
                "confidence": 0.9,
            }
        ],
    }
    return client, student, routine, reference, payload


def test_session_without_video_and_history_are_private(setup_session):
    client, student, routine, reference, payload = setup_session
    payload.update({"student": routine.instructor_id})
    response = client.post("/api/training/sessions/", payload, format="json")
    assert response.status_code == 201, response.data
    assert response.data["student"] == student.pk
    assert response.data["reference_version"] == 2
    assert response.data["pose_schema_version"] == "pose-v1"
    assert response.data["timing_score"] is None
    assert response.data["overall_score"] is None
    # Coverage is derived from evaluated time, never accepted from the client.
    assert response.data["quality_ratio"] is None
    assert len(response.data["segment_scores"]) == 1
    assert len(response.data["error_events"]) == 1
    assert client.get("/api/training/sessions/").data["count"] == 1
    client.force_authenticate(routine.instructor)
    assert client.get("/api/training/sessions/").data["count"] == 0
    assert client.get(f"/api/training/sessions/{payload['id']}/").status_code == 404
    client.force_authenticate(None)
    assert client.get("/api/training/sessions/").status_code == 401


def test_duplicate_upload_is_idempotent_without_duplicate_children(setup_session):
    client, _, _, _, payload = setup_session
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 201
    retry = client.post("/api/training/sessions/", payload, format="json")
    assert retry.status_code == 200
    assert retry.data["id"] == payload["id"]
    session = DanceSession.objects.get()
    assert session.segment_scores.count() == session.error_events.count() == 1


def test_uuid_of_another_student_conflicts(setup_session):
    client, _, _, _, payload = setup_session
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 201
    other = User.objects.create_user(username="other", email="o@example.com")
    client.force_authenticate(other)
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 409
    assert DanceSession.objects.get().student.username == "student"


def test_reference_version_must_match_given_reference(setup_session):
    client, _, _, _, payload = setup_session
    payload["reference_version"] = 99
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    assert DanceSession.objects.count() == 0


@pytest.mark.parametrize(
    "field,value",
    [
        ("pose_score", -1),
        ("pose_score", 101),
        ("pose_score", "NaN"),
        ("finished_at", "2026-10-01T11:00:00Z"),
        ("finished_at", None),
        ("status", "STARTED"),
    ],
)
def test_invalid_summary_does_not_write_partial_data(setup_session, field, value):
    client, _, _, _, payload = setup_session
    payload[field] = value
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    assert DanceSession.objects.count() == 0


def test_wrong_or_unready_reference_rejected(setup_session):
    client, _, routine, reference, payload = setup_session
    other = Routine.objects.create(
        name="Other", instructor=routine.instructor, difficulty="BEGINNER"
    )
    payload["routine"] = other.pk
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    payload["routine"] = routine.pk
    reference.status = "PENDING"
    reference.save()
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400


def test_inactive_routine_cannot_receive_student_session(setup_session):
    client, _, routine, _, payload = setup_session
    routine.is_active = False
    routine.save()
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400


def test_duplicate_segments_or_invalid_events_rejected(setup_session):
    client, _, _, _, payload = setup_session
    payload["segment_scores"] *= 2
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    payload["segment_scores"] = []
    payload["error_events"][0]["end_ms"] = 999
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    payload["error_events"][0]["end_ms"] = 31000
    assert client.post("/api/training/sessions/", payload, format="json").status_code == 400
    assert DanceSession.objects.count() == 0


def test_reference_endpoint_uses_latest_ready_and_respects_catalog_permissions(setup_session):
    client, _, routine, reference, _ = setup_session
    RoutineReference.objects.create(routine=routine, version=3, status="PROCESSING")
    response = client.get(f"/api/routines/{routine.pk}/reference/")
    assert response.status_code == 200
    assert response.data["version"] == reference.version
    assert response.data["reference_asset"].endswith("references/demo.json.gz")
    reference.status = "FAILED"
    reference.save()
    assert client.get(f"/api/routines/{routine.pk}/reference/").status_code == 404
    routine.is_active = False
    routine.save()
    assert client.get(f"/api/routines/{routine.pk}/reference/").status_code == 404
