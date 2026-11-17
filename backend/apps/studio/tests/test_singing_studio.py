"""The studio with singing routines: voice uploads, no pose report, no steps."""

import gzip
import json

import pytest
from django.core.cache import cache
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Course
from apps.routines.models import Routine, RoutineReference

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def isolated(settings, tmp_path, monkeypatch):
    settings.MEDIA_ROOT = tmp_path
    cache.clear()
    seconds = {"value": 60.0}
    queued = []
    monkeypatch.setattr("apps.studio.services.probe_voice", lambda upload: seconds["value"])
    monkeypatch.setattr("apps.studio.services.probe", lambda upload: None)
    monkeypatch.setattr(
        "apps.routines.services.queue_reference", lambda routine_id: queued.append(routine_id)
    )
    return {"seconds": seconds, "queued": queued}


@pytest.fixture
def teacher():
    return User.objects.create_user(
        username="profe", email="profe@example.com", password="x", role="INSTRUCTOR"
    )


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


def upload(client, filename="voz.m4a", kind="SING"):
    voice = SimpleUploadedFile(filename, b"voice-bytes", content_type="audio/mp4")
    return client.post(
        "/api/studio/routines/",
        {"name": "Mi canción", "kind": kind, "difficulty": "BEGINNER", "master_video": voice},
        format="multipart",
    )


def test_an_instructor_uploads_a_voice_for_a_singing_routine(teacher, isolated):
    response = upload(client_for(teacher))
    assert response.status_code == 201, response.json()
    body = response.json()
    assert body["kind"] == "SING"
    routine = Routine.objects.get(pk=body["id"])
    assert routine.is_singing
    assert isolated["queued"] == [routine.pk]


def test_voice_files_are_checked_for_type_and_length(teacher, isolated):
    client = client_for(teacher)
    wrong = upload(client, filename="letra.txt")
    assert wrong.status_code == 400
    assert "M4A" in json.dumps(wrong.json(), ensure_ascii=False)
    isolated["seconds"]["value"] = 400.0
    long = upload(client)
    assert long.status_code == 400
    assert "5 minutos" in json.dumps(long.json(), ensure_ascii=False)
    isolated["seconds"]["value"] = None
    unreadable = upload(client)
    assert unreadable.status_code == 400
    # A dance routine still needs a video.
    assert upload(client, kind="DANCE").status_code == 400
    assert Routine.objects.count() == 0


def test_a_routine_never_switches_between_dance_and_singing(teacher):
    client = client_for(teacher)
    routine_id = upload(client).json()["id"]
    response = client.patch(
        f"/api/studio/routines/{routine_id}/", {"kind": "DANCE"}, format="multipart"
    )
    assert response.status_code == 400
    assert Routine.objects.get(pk=routine_id).kind == "SING"


def _ready_melody(routine, warnings=()):
    artifact = {"schema_version": "pitch-reference-v1", "frames": {"midi": []}}
    return RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        feature_schema="pitch-reference-v1",
        sample_rate_hz=31,
        source_video=routine.master_video.name,
        reference_asset=ContentFile(gzip.compress(json.dumps(artifact).encode()), "ref.json.gz"),
        checksum_sha256="a" * 64,
        duration_ms=12000,
        scoring_profile={"voice_quality": {"warnings": list(warnings)}},
    )


def test_a_singing_routine_publishes_without_pose_report_or_steps(teacher):
    client = client_for(teacher)
    routine = Routine.objects.get(pk=upload(client).json()["id"])
    _ready_melody(routine, warnings=["NOT_VOICE_ONLY"])
    course = Course.objects.create(name="Coro", instructor=teacher, join_code="CORO2345")

    detail = client.get(f"/api/studio/routines/{routine.pk}/").json()
    assert detail["processing"]["warnings"] == ["NOT_VOICE_ONLY"]
    assert client.get(f"/api/studio/routines/{routine.pk}/quality/").status_code == 404
    steps = client.put(
        f"/api/studio/routines/{routine.pk}/choreography/",
        {"bpm": 90, "first_beat_ms": 0, "steps": []},
        format="json",
    )
    assert steps.status_code == 409

    published = client.post(
        f"/api/studio/routines/{routine.pk}/publish/",
        {"courses": [course.pk], "music_rights": "OWN"},
        format="json",
    )
    assert published.status_code == 200, published.json()
    assert published.json()["is_published"] is True
    # Publishing does not create a frozen copy: there is nothing to freeze.
    assert routine.references.count() == 1
