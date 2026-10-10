import gzip
import hashlib
import json

import pytest
from rest_framework.exceptions import ValidationError
from rest_framework.test import APIClient

from ai_engine.choreography.curriculum import GENERATOR_VERSION, STANDARD_V1
from apps.accounts.models import User
from apps.routines import standard
from apps.routines.models import Routine, RoutineReference
from apps.routines.reference_services import queue_reference

pytestmark = pytest.mark.django_db
FAKE_VIDEO = b"rendered coach"


def renderer(spec, directory):
    # Media rendering is covered in ai_engine; here only the installation.
    return FAKE_VIDEO


def test_install_creates_ready_exact_references_without_the_worker(monkeypatch):
    dispatched = []
    monkeypatch.setattr(
        "apps.routines.reference_services._dispatch", lambda pk: dispatched.append(pk)
    )
    created = standard.install(STANDARD_V1[:2], renderer=renderer, log=lambda _: None)
    assert created == 2
    assert dispatched == []
    routine = Routine.objects.get(catalog_key="estandar-n1-marcha")
    assert routine.generator == GENERATOR_VERSION
    assert routine.style == "Estándar N1"
    assert routine.master_video.read() == FAKE_VIDEO
    reference = routine.references.get()
    assert reference.status == RoutineReference.Status.READY
    payload = reference.reference_asset.read()
    assert hashlib.sha256(payload).hexdigest() == reference.checksum_sha256
    artifact = json.loads(gzip.decompress(payload))
    assert artifact["engine"] == GENERATOR_VERSION
    assert artifact["source_sha256"] == hashlib.sha256(FAKE_VIDEO).hexdigest()
    assert routine.duration_ms == reference.duration_ms == artifact["duration_ms"]


def test_install_is_idempotent_and_filters_by_key():
    assert standard.install(renderer=renderer, only=["n1-marcha"], log=lambda _: None) == 1
    assert standard.install(renderer=renderer, only=["n1-marcha"], log=lambda _: None) == 0
    assert Routine.objects.count() == 1


def test_generated_routines_never_go_through_pose_detection():
    standard.install(STANDARD_V1[:1], renderer=renderer, log=lambda _: None)
    routine = Routine.objects.get()
    with pytest.raises(ValidationError, match="coreografía"):
        queue_reference(routine_id=routine.pk)
    assert routine.references.count() == 1


def test_students_can_download_the_generated_reference():
    standard.install(STANDARD_V1[:1], renderer=renderer, log=lambda _: None)
    routine = Routine.objects.get()
    student = User.objects.create_user(username="alumno", email="a@example.com")
    client = APIClient()
    client.force_authenticate(student)
    metadata = client.get(f"/api/routines/{routine.pk}/reference/").data
    assert metadata["status"] == "READY"
    assert metadata["engine_name"] == GENERATOR_VERSION
    listed = client.get("/api/routines/").data["results"][0]
    assert listed["generator"] == GENERATOR_VERSION
    assert listed["credit"].startswith("SyncDance")


def test_refresh_publishes_a_new_version_only_when_the_result_changes():
    standard.install(STANDARD_V1[:1], renderer=renderer, log=lambda _: None)
    routine = Routine.objects.get()
    first_video = routine.master_video.name
    assert (
        standard.install(STANDARD_V1[:1], renderer=renderer, refresh=True, log=lambda _: None) == 0
    )
    assert routine.references.count() == 1

    def new_renderer(spec, directory):
        return b"re-rendered coach"

    assert (
        standard.install(STANDARD_V1[:1], renderer=new_renderer, refresh=True, log=lambda _: None)
        == 1
    )
    routine.refresh_from_db()
    assert list(routine.references.values_list("version", flat=True)) == [2, 1]
    newest, previous = routine.references.all()
    assert newest.status == previous.status == RoutineReference.Status.READY
    assert routine.master_video.read() == b"re-rendered coach"
    assert newest.source_video.name == routine.master_video.name != first_video
    assert previous.source_video.name == first_video
    assert newest.source_sha256 == hashlib.sha256(b"re-rendered coach").hexdigest()
