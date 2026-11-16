import gzip
import hashlib
import json
from datetime import timedelta
from unittest.mock import Mock

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import transaction
from django.utils import timezone
from rest_framework.test import APIClient

from ai_engine.pose.reference import ReferenceError
from apps.accounts.models import User
from apps.routines.models import Routine, RoutineReference
from apps.routines.reference_services import queue_reference
from apps.routines.services import create_routine, update_routine
from apps.routines.tasks import expire_stale_references, generate_reference

pytestmark = pytest.mark.django_db


def test_versioned_video_preserves_source_and_requires_routine_access(setup):
    routine, client, _ = setup
    reference = RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        source_video=routine.master_video.name,
        source_sha256=hashlib.sha256(b"fixture video").hexdigest(),
    )
    routine.master_video = SimpleUploadedFile("new.mp4", b"new master")
    routine.save()
    url = f"/api/routines/{routine.pk}/references/1/video/"
    response = client.get(url)
    assert response.status_code == 200
    assert b"".join(response.streaming_content) == b"fixture video"
    assert response["ETag"] == f'"{reference.source_sha256}"'
    response.close()

    client.force_authenticate(None)
    assert client.get(url).status_code == 401
    student = User.objects.create_user(username="student-video", email="sv@example.com")
    client.force_authenticate(student)
    response = client.get(url)
    assert response.status_code == 200
    response.close()
    routine.is_active = False
    routine.save()
    assert client.get(url).status_code == 404
    client.force_authenticate(routine.instructor)
    reference.status = "PROCESSING"
    reference.save()
    assert client.get(url).status_code == 404
    reference.status = "READY"
    reference.save()
    reference.source_video.storage.delete(reference.source_video.name)
    assert client.get(url).status_code == 404


@pytest.fixture
def setup(settings, tmp_path, monkeypatch):
    settings.MEDIA_ROOT = tmp_path
    teacher = User.objects.create_user(
        username="teacher", email="teacher@example.com", role="INSTRUCTOR"
    )
    routine = Routine.objects.create(
        name="Demo",
        instructor=teacher,
        difficulty="BEGINNER",
        master_video=SimpleUploadedFile("master.mp4", b"fixture video"),
    )
    dispatch = Mock()
    monkeypatch.setattr(generate_reference, "delay", dispatch)
    client = APIClient()
    client.force_authenticate(teacher)
    return routine, client, dispatch


@pytest.fixture
def engine(monkeypatch):
    artifact = {
        "source_sha256": "b" * 64,
        "engine": "fixture",
        "algorithm_version": "test-v1",
        "duration_ms": 1000,
    }
    payload = gzip.compress(json.dumps(artifact).encode(), mtime=0)
    build = Mock(return_value=(payload, artifact))
    monkeypatch.setattr("apps.routines.tasks.build_reference", build)
    return build, payload


def test_queue_on_commit_reuses_pending_and_increments_after_completion(
    setup, django_capture_on_commit_callbacks
):
    routine, _, dispatch = setup
    with django_capture_on_commit_callbacks(execute=True):
        ref = queue_reference(routine_id=routine.pk)
        assert queue_reference(routine_id=routine.pk).pk == ref.pk
        dispatch.assert_not_called()
    dispatch.assert_called_once_with(ref.pk)
    ref.status = "FAILED"
    ref.save()
    with django_capture_on_commit_callbacks(execute=True):
        newer = queue_reference(routine_id=routine.pk)
    assert newer.version == 2
    assert newer.source_video.name == routine.master_video.name


def test_transaction_rollback_does_not_dispatch(setup, django_capture_on_commit_callbacks):
    routine, _, dispatch = setup
    with (
        django_capture_on_commit_callbacks(execute=True),
        pytest.raises(ValueError),
        transaction.atomic(),
    ):
        queue_reference(routine_id=routine.pk)
        raise ValueError("rollback")
    assert RoutineReference.objects.count() == 0
    dispatch.assert_not_called()


def test_stalled_worker_can_be_replaced_by_new_version(setup):
    routine, _, _ = setup
    old = queue_reference(routine_id=routine.pk)
    old.status = "PROCESSING"
    old.processing_started_at = timezone.now() - timedelta(minutes=32)
    old.save()
    newer = queue_reference(routine_id=routine.pk)
    old.refresh_from_db()
    assert old.status == "FAILED"
    assert newer.version == old.version + 1


def test_periodic_sweep_recovers_only_references_past_the_hard_limit(setup):
    routine, _, _ = setup
    stale = queue_reference(routine_id=routine.pk)
    stale.status = "PROCESSING"
    stale.processing_started_at = timezone.now() - timedelta(minutes=32)
    stale.save()
    running = RoutineReference.objects.create(
        routine=routine,
        version=stale.version + 1,
        status="PROCESSING",
        processing_started_at=timezone.now() - timedelta(minutes=5),
    )
    never_started = RoutineReference.objects.create(
        routine=routine, version=stale.version + 2, status="PENDING"
    )
    RoutineReference.objects.filter(pk=never_started.pk).update(
        created_at=timezone.now() - timedelta(minutes=40)
    )
    assert expire_stale_references.run() == 2
    assert expire_stale_references.run() == 0
    statuses = dict(RoutineReference.objects.values_list("pk", "status"))
    assert statuses[stale.pk] == "FAILED"
    assert statuses[never_started.pk] == "FAILED"
    assert statuses[running.pk] == "PROCESSING"


def test_dispatch_failure_is_visible(setup, django_capture_on_commit_callbacks):
    routine, _, dispatch = setup
    dispatch.side_effect = OSError("broker unavailable")
    with django_capture_on_commit_callbacks(execute=True):
        ref = queue_reference(routine_id=routine.pk)
    ref.refresh_from_db()
    assert ref.status == "FAILED"
    assert "enviar" in ref.processing_error


def test_task_persists_hash_duration_and_duplicate_is_noop(setup, engine):
    routine, client, _ = setup
    build, payload = engine
    ref = queue_reference(routine_id=routine.pk)
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    routine.refresh_from_db()
    assert ref.status == "READY"
    assert ref.checksum_sha256 == hashlib.sha256(payload).hexdigest()
    assert routine.duration_ms == 1000
    with ref.reference_asset.open("rb") as data:
        assert data.read() == payload
    generate_reference.run(ref.pk)
    build.assert_called_once()
    response = client.get(f"/api/routines/{routine.pk}/reference/")
    assert response.status_code == 200
    download = client.get(response.data["download_url"])
    assert b"".join(download.streaming_content) == payload
    assert download["ETag"] == f'"{ref.checksum_sha256}"'
    download.close()


def test_failure_not_ready_and_does_not_expose_native_paths(setup, engine):
    routine, client, _ = setup
    build, _ = engine
    build.side_effect = RuntimeError("private path or token")
    ref = queue_reference(routine_id=routine.pk)
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    assert ref.status == "FAILED"
    assert not ref.reference_asset
    response = client.get(f"/api/routines/{routine.pk}/reference-status/")
    assert "private" not in response.data["processing_error"]
    assert response.data["download_url"] is None
    assert client.get(f"/api/routines/{routine.pk}/reference/").status_code == 404


def test_user_actionable_failure_and_source_size_limit(setup, engine, monkeypatch):
    routine, _, _ = setup
    build, _ = engine
    build.side_effect = ReferenceError("No hay poses válidas.")
    ref = queue_reference(routine_id=routine.pk)
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    assert ref.processing_error == "No hay poses válidas."
    monkeypatch.setattr("apps.routines.tasks.MAX_SOURCE_BYTES", 1)
    ref = queue_reference(routine_id=routine.pk)
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    assert "200 MB" in ref.processing_error
    assert build.call_count == 1


def test_replacement_keeps_old_version_but_does_not_publish_it_as_current(setup, engine):
    routine, client, _ = setup
    ref = queue_reference(routine_id=routine.pk)
    update_routine(routine=routine, master_video=SimpleUploadedFile("new.mp4", b"new video"))
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    routine.refresh_from_db()
    assert ref.status == "READY"
    assert routine.duration_ms == 0
    assert client.get(f"/api/routines/{routine.pk}/reference/").status_code == 404
    assert client.get(f"/api/routines/{routine.pk}/reference-status/").data["version"] == 2


def test_create_and_update_queue_only_video_changes(setup):
    routine, _, _ = setup
    update_routine(routine=routine, name="Renamed")
    assert routine.references.count() == 0
    created = create_routine(
        instructor=routine.instructor,
        name="New",
        difficulty="BEGINNER",
        master_video=SimpleUploadedFile("fresh.mp4", b"video"),
    )
    assert created.references.count() == 1
    update_routine(routine=created, master_video="")
    assert created.duration_ms == 0


def test_api_permissions_and_missing_video(setup, engine):
    routine, client, _ = setup
    response = client.post(f"/api/routines/{routine.pk}/generate-reference/")
    assert response.status_code == 202
    generate_reference.run(response.data["id"])
    download_url = client.get(f"/api/routines/{routine.pk}/reference/").data["download_url"]
    other = User.objects.create_user(username="other", email="o@example.com", role="INSTRUCTOR")
    client.force_authenticate(other)
    assert client.get(download_url).status_code == 404
    assert client.post(f"/api/routines/{routine.pk}/generate-reference/").status_code == 404
    other.role = "STUDENT"
    other.save()
    assert client.post(f"/api/routines/{routine.pk}/generate-reference/").status_code == 403
    routine.is_active = False
    routine.save()
    assert client.get(download_url).status_code == 404
    client.force_authenticate(None)
    assert client.get(download_url).status_code == 401
    client.force_authenticate(routine.instructor)
    update_routine(routine=routine, master_video="")
    assert client.post(f"/api/routines/{routine.pk}/generate-reference/").status_code == 400


def test_processing_is_traceable_by_task_id_and_time(
    setup, engine, caplog, django_capture_on_commit_callbacks
):
    routine, _, dispatch = setup
    dispatch.return_value = Mock(id="task-123")
    with django_capture_on_commit_callbacks(execute=True):
        ref = queue_reference(routine_id=routine.pk)
    ref.refresh_from_db()
    assert ref.processing_task_id == "task-123"
    assert ref.processing_finished_at is None
    with caplog.at_level("INFO", logger="apps.routines.tasks"):
        generate_reference.run(ref.pk)
    ref.refresh_from_db()
    assert ref.status == "READY"
    # A run outside a worker has no task id: the dispatched one is kept.
    assert ref.processing_task_id == "task-123"
    assert ref.processing_finished_at >= ref.processing_started_at
    (ready,) = [r for r in caplog.records if r.getMessage() == "reference ready"]
    assert ready.reference_id == ref.pk
    assert ready.elapsed_ms >= 0


def test_failed_processing_records_when_it_ended(setup, engine):
    routine, _, _ = setup
    build, _ = engine
    build.side_effect = ReferenceError("Sin persona visible.")
    ref = queue_reference(routine_id=routine.pk)
    generate_reference.run(ref.pk)
    ref.refresh_from_db()
    assert ref.status == "FAILED"
    assert ref.processing_finished_at is not None
