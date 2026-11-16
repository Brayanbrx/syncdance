import gzip
import json
import os

import pytest
from django.core.cache import cache
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Assignment, Course, Enrollment
from apps.routines.models import Routine, RoutineReference

GOOD_VIDEO = {"duration": 60.0, "size": (1280, 720)}


@pytest.fixture(autouse=True)
def isolated(settings, tmp_path, monkeypatch):
    """Uploads in a temporary folder; no FFmpeg, no worker."""
    settings.MEDIA_ROOT = tmp_path
    cache.clear()
    probe = {"answer": GOOD_VIDEO}
    queued = []
    monkeypatch.setattr("apps.studio.services.probe", lambda upload: probe["answer"])
    monkeypatch.setattr(
        "apps.routines.services.queue_reference", lambda routine_id: queued.append(routine_id)
    )
    return {"probe": probe, "queued": queued}


@pytest.fixture
def school(db):
    def person(name, role="STUDENT"):
        return User.objects.create_user(
            username=name, email=f"{name}@example.com", password="x", role=role
        )

    teacher, other, ana = person("profe", "INSTRUCTOR"), person("otra", "INSTRUCTOR"), person("ana")
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    other_course = Course.objects.create(name="Danza 2B", instructor=other, join_code="WXYZ6789")
    Enrollment.objects.create(course=course, student=ana)
    return {
        "teacher": teacher,
        "other": other,
        "ana": ana,
        "course": course,
        "other_course": other_course,
    }


def client_for(user=None):
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


def upload(client, name="Mi coreografía", filename="baile.mp4"):
    video = SimpleUploadedFile(filename, b"video-bytes", content_type="video/mp4")
    return client.post(
        "/api/studio/routines/",
        {"name": name, "difficulty": "BEGINNER", "style": "Urbano", "master_video": video},
        format="multipart",
    )


def ready_reference(routine, qualities, rate=12):
    """A processed reference whose samples have the given qualities."""
    frames = [{"t": round(i * 1000 / rate), "quality": q} for i, q in enumerate(qualities)]
    artifact = {"sample_rate_hz": rate, "duration_ms": len(frames) * 1000 // rate, "frames": frames}
    return RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        source_video=routine.master_video.name,
        reference_asset=ContentFile(gzip.compress(json.dumps(artifact).encode()), "ref.json.gz"),
        checksum_sha256="a" * 64,
        duration_ms=artifact["duration_ms"],
    )


def seen_by(user):
    response = client_for(user).get("/api/routines/")
    return [item["name"] for item in response.json()["results"]]


@pytest.mark.django_db
def test_an_upload_is_a_draft_only_its_instructor_sees(school, isolated):
    response = upload(client_for(school["teacher"]))

    assert response.status_code == 201
    body = response.json()
    assert body["is_published"] is False
    assert body["visibility"] == "COURSES"
    assert body["courses"] == []
    routine = Routine.objects.get(pk=body["id"])
    assert isolated["queued"] == [routine.pk]
    assert seen_by(school["ana"]) == []


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("filename", "probe", "message"),
    [
        ("baile.avi", GOOD_VIDEO, "MP4, MOV, WEBM o MKV"),
        ("baile.mp4", {"duration": 400.0, "size": (1280, 720)}, "más de 5 minutos"),
        ("baile.mp4", {"duration": 2.0, "size": (1280, 720)}, "al menos 5 segundos"),
        ("baile.mp4", {"duration": 60.0, "size": (320, 240)}, "360 píxeles"),
        ("baile.mp4", {"duration": None, "size": None}, "No se pudo leer el video"),
    ],
)
def test_the_video_is_checked_when_it_is_uploaded(school, isolated, filename, probe, message):
    isolated["probe"]["answer"] = probe

    response = upload(client_for(school["teacher"]), filename=filename)

    assert response.status_code == 400
    assert message in response.json()["master_video"][0]
    assert not Routine.objects.exists()
    assert isolated["queued"] == []


@pytest.mark.django_db
def test_a_video_over_the_size_limit_is_refused(school, monkeypatch):
    monkeypatch.setattr("apps.studio.services.MAX_SOURCE_BYTES", 5)

    response = upload(client_for(school["teacher"]))

    assert response.status_code == 400
    assert "200 MB" in response.json()["master_video"][0]


@pytest.mark.django_db
def test_only_instructors_use_the_studio_and_each_sees_their_own(school):
    upload(client_for(school["teacher"]), name="Del profe")
    upload(client_for(school["other"]), name="De la otra")

    mine = client_for(school["teacher"]).get("/api/studio/routines/").json()["results"]

    assert [r["name"] for r in mine] == ["Del profe"]
    assert client_for(school["ana"]).get("/api/studio/routines/").status_code == 403
    assert client_for().get("/api/studio/routines/").status_code == 401


@pytest.mark.django_db
def test_publishing_in_a_course_shows_the_routine_to_its_students(school):
    client = client_for(school["teacher"])
    routine = Routine.objects.get(pk=upload(client).json()["id"])
    ready_reference(routine, ["SINGLE_PERSON"] * 48)

    response = client.post(
        f"/api/studio/routines/{routine.pk}/publish/",
        {"courses": [school["course"].pk], "music_rights": "OWN"},
        format="json",
    )

    assert response.status_code == 200
    body = response.json()
    assert body["is_published"] is True
    assert body["courses"] == [school["course"].pk]
    assert body["music_rights"] == "OWN"
    assert body["rights_declared_at"] is not None
    assert body["processing"]["status"] == "READY"
    assert seen_by(school["ana"]) == ["Mi coreografía"]

    hidden = client.post(f"/api/studio/routines/{routine.pk}/unpublish/")
    assert hidden.json()["is_published"] is False
    assert seen_by(school["ana"]) == []


@pytest.mark.django_db
def test_publishing_needs_rights_a_good_reference_and_own_courses(school):
    client = client_for(school["teacher"])
    routine = Routine.objects.get(pk=upload(client).json()["id"])

    def attempt(courses=None, rights="OWN"):
        payload = {"courses": [school["course"].pk] if courses is None else courses}
        if rights:
            payload["music_rights"] = rights
        return client.post(f"/api/studio/routines/{routine.pk}/publish/", payload, format="json")

    assert "music_rights" in attempt(rights=None).json()
    assert attempt().status_code == 409  # still processing
    reference = ready_reference(routine, ["SINGLE_PERSON"] * 12 + ["NO_USABLE_POSE"] * 12)
    refused = attempt()
    assert refused.status_code == 409
    assert "80 %" in refused.json()["detail"]
    reference.delete()
    ready_reference(routine, ["SINGLE_PERSON"] * 24)
    assert "courses" in attempt(courses=[school["other_course"].pk]).json()
    assert "courses" in attempt(courses=[]).json()
    routine.refresh_from_db()
    assert routine.is_published is False
    assert attempt().status_code == 200


@pytest.mark.django_db
def test_the_quality_report_points_at_the_gaps(school):
    client = client_for(school["teacher"])
    routine = Routine.objects.get(pk=upload(client).json()["id"])
    assert client.get(f"/api/studio/routines/{routine.pk}/quality/").status_code == 404
    single = ["SINGLE_PERSON"] * 24
    ready_reference(
        routine,
        single + ["NO_USABLE_POSE"] * 18 + single + ["MULTIPLE_PEOPLE"] * 6 + single,
    )

    report = client.get(f"/api/studio/routines/{routine.pk}/quality/").json()

    assert report["samples"] == 96
    assert report["single_person"] == 0.75
    assert report["no_usable_pose"] == pytest.approx(0.188, abs=0.001)
    assert report["multiple_people"] == pytest.approx(0.062, abs=0.001)
    # The 1.5 s gap is shown; half a second with two people is not worth it.
    assert report["problems"] == [{"start_ms": 2000, "end_ms": 3500, "kind": "NO_USABLE_POSE"}]
    assert report["publishable"] is False


@pytest.mark.django_db
def test_a_new_video_sends_the_routine_back_to_draft(school, isolated):
    client = client_for(school["teacher"])
    routine = Routine.objects.get(pk=upload(client).json()["id"])
    ready_reference(routine, ["SINGLE_PERSON"] * 24)
    client.post(
        f"/api/studio/routines/{routine.pk}/publish/",
        {"courses": [school["course"].pk], "music_rights": "LICENSED"},
        format="json",
    )

    video = SimpleUploadedFile("nuevo.mp4", b"other-bytes", content_type="video/mp4")
    response = client.patch(
        f"/api/studio/routines/{routine.pk}/", {"master_video": video}, format="multipart"
    )

    assert response.status_code == 200
    assert response.json()["is_published"] is False
    assert response.json()["processing"] is None  # the new video is not processed yet
    assert isolated["queued"] == [routine.pk, routine.pk]
    assert seen_by(school["ana"]) == []


@pytest.mark.django_db
def test_only_an_unused_routine_can_be_deleted(school, django_capture_on_commit_callbacks):
    client = client_for(school["teacher"])
    unused = Routine.objects.get(pk=upload(client, name="Sin usar").json()["id"])
    assigned = Routine.objects.get(pk=upload(client, name="Con tarea").json()["id"])
    Assignment.objects.create(
        course=school["course"], routine=assigned, target_stars=3, due_date=timezone.localdate()
    )
    stored = unused.master_video.path

    with django_capture_on_commit_callbacks(execute=True):
        deleted = client.delete(f"/api/studio/routines/{unused.pk}/")
    kept = client.delete(f"/api/studio/routines/{assigned.pk}/")

    assert deleted.status_code == 204
    assert not Routine.objects.filter(pk=unused.pk).exists()
    assert not os.path.exists(stored)
    assert kept.status_code == 409
    assert Routine.objects.filter(pk=assigned.pk).exists()


@pytest.mark.django_db
def test_the_course_list_offers_only_the_instructors_courses(school):
    courses = client_for(school["teacher"]).get("/api/studio/courses/").json()

    assert courses == [
        {
            "id": school["course"].pk,
            "name": "Danza 1A",
            "join_code": "ABCD2345",
            "accepts_students": True,
            "students": 1,
        }
    ]
