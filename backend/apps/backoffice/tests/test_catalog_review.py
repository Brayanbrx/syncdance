"""An instructor proposes a published routine for the free catalog and a
platform administrator approves or rejects it from the panel."""

import gzip
import json

import pytest
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Course, Enrollment
from apps.routines.models import Routine, RoutineReference

pytestmark = pytest.mark.django_db


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


def seen_by(user):
    return [r["name"] for r in client_for(user).get("/api/routines/").json()["results"]]


def ready_reference(routine, version=1):
    frames = [{"t": round(i * 1000 / 12), "quality": "SINGLE_PERSON"} for i in range(24)]
    artifact = {"sample_rate_hz": 12, "duration_ms": 2000, "frames": frames}
    return RoutineReference.objects.create(
        routine=routine,
        version=version,
        status="READY",
        source_video=routine.master_video.name,
        reference_asset=ContentFile(gzip.compress(json.dumps(artifact).encode()), "ref.json.gz"),
        checksum_sha256="a" * 64,
        duration_ms=2000,
    )


@pytest.fixture
def world(settings, tmp_path, monkeypatch):
    """A routine its instructor already published in their course."""
    settings.MEDIA_ROOT = tmp_path
    monkeypatch.setattr(
        "apps.studio.services.probe", lambda upload: {"duration": 60.0, "size": (1280, 720)}
    )
    monkeypatch.setattr("apps.routines.services.queue_reference", lambda routine_id: None)

    def person(name, role="STUDENT"):
        return User.objects.create_user(username=name, email=f"{name}@example.com", role=role)

    teacher, admin = person("profe", "INSTRUCTOR"), person("jefa", "ADMIN")
    ana, leo = person("ana"), person("leo")  # ana takes the course, leo does not
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    Enrollment.objects.create(course=course, student=ana)
    studio = client_for(teacher)
    created = studio.post(
        "/api/studio/routines/",
        {
            "name": "Salsa en línea",
            "difficulty": "BEGINNER",
            "master_video": SimpleUploadedFile("salsa.mp4", b"video", content_type="video/mp4"),
        },
        format="multipart",
    ).json()
    routine = Routine.objects.get(pk=created["id"])
    ready_reference(routine)
    published = studio.post(
        f"/api/studio/routines/{routine.pk}/publish/",
        {"courses": [course.pk], "music_rights": "OWN"},
        format="json",
    )
    assert published.status_code == 200
    return {
        "routine": routine,
        "studio": studio,
        "panel": client_for(admin),
        "ana": ana,
        "leo": leo,
        "catalog": f"/api/studio/routines/{routine.pk}/catalog/",
        "proposal": f"/api/panel/proposals/{routine.pk}",
    }


def test_an_approved_routine_reaches_every_student(world):
    studio, panel = world["studio"], world["panel"]
    assert seen_by(world["leo"]) == []

    proposed = studio.post(world["catalog"])
    assert proposed.status_code == 200
    assert proposed.json()["catalog_review"] == "PENDING"
    assert proposed.json()["catalog_requested_at"] is not None
    assert studio.post(world["catalog"]).status_code == 409
    assert panel.get("/api/panel/summary/").data["catalog"]["proposals_pending"] == 1
    (queued,) = panel.get("/api/panel/proposals/").json()
    assert queued["name"] == "Salsa en línea"
    assert queued["instructor"] == "profe"
    assert queued["courses"] == 1
    assert queued["single_person"] == 1.0
    assert queued["processing"]["version"] == 1
    assert queued["music_rights"] == "OWN"

    assert panel.post(f"{world['proposal']}/approve/").status_code == 204

    assert seen_by(world["leo"]) == ["Salsa en línea"]
    routine = studio.get(f"/api/studio/routines/{world['routine'].pk}/").json()
    assert routine["visibility"] == "CATALOG"
    assert routine["catalog_review"] == "APPROVED"
    assert panel.get("/api/panel/proposals/").json() == []
    assert panel.post(f"{world['proposal']}/approve/").status_code == 404


def test_a_rejection_tells_the_instructor_why(world):
    studio, panel = world["studio"], world["panel"]
    studio.post(world["catalog"])

    silent = panel.post(f"{world['proposal']}/reject/", {"note": "  "}, format="json")
    assert silent.status_code == 400
    assert "note" in silent.json()
    rejected = panel.post(
        f"{world['proposal']}/reject/", {"note": "Se corta el final del paso."}, format="json"
    )
    assert rejected.status_code == 204

    routine = studio.get(f"/api/studio/routines/{world['routine'].pk}/").json()
    assert routine["catalog_review"] == "REJECTED"
    assert routine["catalog_review_note"] == "Se corta el final del paso."
    assert routine["visibility"] == "COURSES"
    assert seen_by(world["leo"]) == []
    # After fixing it, the instructor proposes again.
    again = studio.post(world["catalog"]).json()
    assert again["catalog_review"] == "PENDING"
    assert again["catalog_review_note"] == ""


def test_only_a_published_routine_can_be_proposed(world):
    studio = world["studio"]
    studio.post(f"/api/studio/routines/{world['routine'].pk}/unpublish/")
    refused = studio.post(world["catalog"])
    assert refused.status_code == 409
    assert "Publícala" in refused.json()["detail"]
    assert studio.delete(world["catalog"]).status_code == 409  # nothing to withdraw


def test_leaving_the_catalog_keeps_the_courses(world):
    studio, panel = world["studio"], world["panel"]
    studio.post(world["catalog"])
    panel.post(f"{world['proposal']}/approve/")

    withdrawn = studio.delete(world["catalog"])

    assert withdrawn.status_code == 200
    assert withdrawn.json()["visibility"] == "COURSES"
    assert withdrawn.json()["is_published"] is True
    assert seen_by(world["ana"]) == ["Salsa en línea"]
    assert seen_by(world["leo"]) == []


def test_a_new_video_needs_a_new_review(world):
    studio, panel = world["studio"], world["panel"]
    studio.post(world["catalog"])
    panel.post(f"{world['proposal']}/approve/")

    replaced = studio.patch(
        f"/api/studio/routines/{world['routine'].pk}/",
        {"master_video": SimpleUploadedFile("nuevo.mp4", b"other", content_type="video/mp4")},
        format="multipart",
    ).json()

    assert replaced["visibility"] == "COURSES"
    assert replaced["catalog_review"] == ""
    assert replaced["is_published"] is False
    assert seen_by(world["leo"]) == []


def test_retiring_takes_the_routine_out_of_the_catalog(world):
    studio, panel = world["studio"], world["panel"]
    url = f"/api/studio/routines/{world['routine'].pk}/"
    studio.post(world["catalog"])
    panel.post(f"{world['proposal']}/approve/")

    retired = studio.post(f"{url}unpublish/").json()

    assert retired["visibility"] == "COURSES"
    assert retired["catalog_review"] == ""
    # Published again in the course, it does not come back to the catalog alone.
    courses = [c["id"] for c in studio.get("/api/studio/courses/").json()]
    studio.post(f"{url}publish/", {"courses": courses, "music_rights": "OWN"}, format="json")
    assert seen_by(world["ana"]) == ["Salsa en línea"]
    assert seen_by(world["leo"]) == []


def test_a_late_answer_finds_the_proposal_gone(world):
    studio, panel = world["studio"], world["panel"]
    studio.post(world["catalog"])
    studio.delete(world["catalog"])  # the instructor changed their mind
    assert panel.post(f"{world['proposal']}/approve/").status_code == 404

    studio.post(world["catalog"])
    Routine.objects.filter(pk=world["routine"].pk).update(is_active=False)
    hidden = panel.post(f"{world['proposal']}/approve/")
    assert hidden.status_code == 409
    assert seen_by(world["leo"]) == []


def test_the_review_queue_is_only_for_platform_admins(world):
    for user in (world["ana"], world["routine"].instructor):
        client = client_for(user)
        assert client.get("/api/panel/proposals/").status_code == 403
        assert client.post(f"{world['proposal']}/approve/").status_code == 403
