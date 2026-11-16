"""Tempo and steps: the draft in the studio and what publishing freezes."""

import gzip
import json
from pathlib import Path

import pytest
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Course, Enrollment
from apps.routines.models import Routine, RoutineReference
from apps.studio import choreography
from apps.studio.choreography import ChoreographyError

FIXTURE = Path(__file__).resolve().parents[4] / (
    "mobile/test/fixtures/references/scoring_profile_v1.json"
)


@pytest.fixture
def contract():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def test_the_phone_receives_the_profile_of_the_shared_fixture(contract):
    duration = contract["duration_ms"]
    cleaned = choreography.clean(contract["draft"], duration_ms=duration)
    assert choreography.profile(cleaned, duration_ms=duration) == contract["profile"]


def test_steps_are_kept_in_order_and_trimmed(contract):
    draft = dict(contract["draft"])
    draft["steps"] = [
        {"name": "  Giro ", "start_beat": 8, "counts": 4, "tip": " "},
        {"name": "Paso cruzado", "start_beat": 0, "counts": 8},
    ]
    cleaned = choreography.clean(draft, duration_ms=15000)
    assert [s["name"] for s in cleaned["steps"]] == ["Paso cruzado", "Giro"]
    assert cleaned["steps"][1]["tip"] == ""


@pytest.mark.parametrize(
    ("change", "field", "message"),
    [
        ({"bpm": None}, "bpm", "tempo antes"),
        ({"bpm": 200}, "bpm", "entre 60 y 180"),
        ({"first_beat_ms": 15000}, "first_beat_ms", "dentro del video"),
        (
            {
                "steps": [
                    {"name": "A", "start_beat": 0, "counts": 8},
                    {"name": "B", "start_beat": 6, "counts": 4},
                ]
            },
            "steps",
            "paso 2 empieza antes",
        ),
        ({"steps": [{"name": "A", "start_beat": 20, "counts": 8}]}, "steps", "después del final"),
        ({"steps": [{"name": "  ", "start_beat": 0, "counts": 8}]}, "steps", "nombre al paso 1"),
    ],
)
def test_impossible_drafts_are_refused(contract, change, field, message):
    draft = {**contract["draft"], **change}
    with pytest.raises(ChoreographyError, match=message) as error:
        choreography.clean(draft, duration_ms=15000)
    assert error.value.field == field


def test_a_tempo_without_steps_still_times_the_game():
    cleaned = choreography.clean({"bpm": 100, "first_beat_ms": 0, "steps": []}, duration_ms=9000)
    assert choreography.profile(cleaned, duration_ms=9000) == {
        "beat_grid": {
            "version": "beat-grid-v1",
            "bpm": 100.0,
            "first_beat_ms": 0,
            "beats_per_move": 2,
        }
    }
    assert choreography.clean({"bpm": None, "first_beat_ms": None}, duration_ms=9000) == {}


# --- through the studio API ---------------------------------------------------


def ready(routine, version=1, profile=None):
    frames = [{"t": round(i * 1000 / 12), "quality": "SINGLE_PERSON"} for i in range(180)]
    artifact = {"sample_rate_hz": 12, "duration_ms": 15000, "frames": frames}
    return RoutineReference.objects.create(
        routine=routine,
        version=version,
        status="READY",
        source_video=routine.master_video.name,
        reference_asset=ContentFile(gzip.compress(json.dumps(artifact).encode()), "ref.json.gz"),
        playback_video=ContentFile(b"light", "app.mp4"),
        poster=ContentFile(b"jpeg", "poster.jpg"),
        playback_profile="app-video-v1",
        checksum_sha256="a" * 64,
        source_sha256="b" * 64,
        duration_ms=15000,
        scoring_profile=profile or {},
    )


@pytest.fixture
def studio(db, settings, tmp_path, monkeypatch):
    settings.MEDIA_ROOT = tmp_path
    monkeypatch.setattr(
        "apps.studio.services.probe", lambda upload: {"duration": 15.0, "size": (1280, 720)}
    )
    monkeypatch.setattr("apps.routines.services.queue_reference", lambda routine_id: None)
    teacher = User.objects.create_user(username="profe", email="p@example.com", role="INSTRUCTOR")
    ana = User.objects.create_user(username="ana", email="a@example.com")
    course = Course.objects.create(name="Danza", instructor=teacher, join_code="ABCD2345")
    Enrollment.objects.create(course=course, student=ana)
    client = APIClient()
    client.force_authenticate(teacher)
    routine_id = client.post(
        "/api/studio/routines/",
        {
            "name": "Salsa",
            "difficulty": "BEGINNER",
            "master_video": SimpleUploadedFile("salsa.mp4", b"video", content_type="video/mp4"),
        },
        format="multipart",
    ).json()["id"]
    student = APIClient()
    student.force_authenticate(ana)
    return {
        "client": client,
        "student": student,
        "routine": Routine.objects.get(pk=routine_id),
        "course": course,
        "url": f"/api/studio/routines/{routine_id}/",
    }


def publish(studio):
    return studio["client"].post(
        f"{studio['url']}publish/",
        {"courses": [studio["course"].pk], "music_rights": "OWN"},
        format="json",
    )


@pytest.mark.django_db
def test_the_tempo_waits_for_a_processed_video(studio, contract):
    saved = studio["client"].put(f"{studio['url']}choreography/", contract["draft"], format="json")
    assert saved.status_code == 409
    assert "procesamiento" in saved.json()["detail"]


@pytest.mark.django_db
def test_publishing_freezes_tempo_and_steps_without_reprocessing(studio, contract):
    client, routine = studio["client"], studio["routine"]
    first = ready(routine)

    saved = client.put(f"{studio['url']}choreography/", contract["draft"], format="json")

    assert saved.status_code == 200
    state = saved.json()["choreography"]
    assert state["bpm"] == 112.0
    assert [s["name"] for s in state["steps"]] == ["Paso cruzado", "Giro", "Cierre con brazos"]
    assert state["stale"] is False
    assert state["unpublished_changes"] is False  # not published yet
    assert routine.references.count() == 1  # a draft never touches a READY version

    assert publish(studio).status_code == 200

    frozen = routine.references.get(version=2)
    assert frozen.scoring_profile == contract["profile"]
    for field in ("reference_asset", "playback_video", "poster", "source_video"):
        assert getattr(frozen, field).name == getattr(first, field).name
    assert frozen.checksum_sha256 == first.checksum_sha256
    first.refresh_from_db()
    assert first.scoring_profile == {}
    seen = studio["student"].get(f"/api/routines/{routine.pk}/reference/").json()
    assert seen["version"] == 2
    assert seen["scoring_profile"] == contract["profile"]
    # Publishing again with nothing new keeps the version.
    assert publish(studio).status_code == 200
    assert routine.references.count() == 2


@pytest.mark.django_db
def test_changes_after_publishing_wait_for_the_next_publish(studio, contract):
    client, routine = studio["client"], studio["routine"]
    ready(routine)
    client.put(f"{studio['url']}choreography/", contract["draft"], format="json")
    publish(studio)

    fewer = {**contract["draft"], "steps": contract["draft"]["steps"][:1]}
    state = client.put(f"{studio['url']}choreography/", fewer, format="json").json()

    assert state["choreography"]["unpublished_changes"] is True
    seen = studio["student"].get(f"/api/routines/{routine.pk}/reference/").json()
    assert len(seen["scoring_profile"]["steps"]["items"]) == 3
    publish(studio)
    seen = studio["student"].get(f"/api/routines/{routine.pk}/reference/").json()
    assert seen["version"] == 3
    assert len(seen["scoring_profile"]["steps"]["items"]) == 1
    cleared = client.put(
        f"{studio['url']}choreography/", {"bpm": None, "first_beat_ms": None}, format="json"
    ).json()
    assert cleared["choreography"]["steps"] == []
    assert cleared["choreography"]["unpublished_changes"] is True


@pytest.mark.django_db
def test_a_new_video_asks_to_check_the_first_beat(studio, contract):
    client, routine = studio["client"], studio["routine"]
    ready(routine)
    client.put(f"{studio['url']}choreography/", contract["draft"], format="json")
    client.patch(
        studio["url"],
        {"master_video": SimpleUploadedFile("otra.mp4", b"other", content_type="video/mp4")},
        format="multipart",
    )
    routine.refresh_from_db()
    ready(routine, version=2)

    state = client.get(studio["url"]).json()["choreography"]
    assert state["stale"] is True
    assert [s["name"] for s in state["steps"]] == ["Paso cruzado", "Giro", "Cierre con brazos"]
    refused = publish(studio)
    assert refused.status_code == 409
    assert "Compás y pasos" in refused.json()["detail"]

    nudged = {**contract["draft"], "first_beat_ms": 900}
    state = client.put(f"{studio['url']}choreography/", nudged, format="json").json()
    assert state["choreography"]["stale"] is False
    assert publish(studio).status_code == 200
    items = routine.references.get(version=3).scoring_profile["steps"]["items"]
    assert items[0]["start_ms"] == 900  # same steps, counted from the new first beat


@pytest.mark.django_db
def test_too_many_counts_are_refused_by_the_api(studio, contract):
    ready(studio["routine"])
    draft = {**contract["draft"], "steps": [{"name": "Largo", "start_beat": 0, "counts": 33}]}
    refused = studio["client"].put(f"{studio['url']}choreography/", draft, format="json")
    assert refused.status_code == 400
    assert "steps" in refused.json()
