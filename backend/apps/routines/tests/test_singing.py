"""Singing routines: the generated exercises, the listing by kind and the
worker turning an instructor's voice into a melody reference."""

import hashlib
import wave
from unittest.mock import Mock

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.routines import singing
from apps.routines.models import Routine, RoutineReference
from apps.routines.reference_services import queue_reference
from apps.routines.tasks import generate_reference

pytestmark = pytest.mark.django_db
FAKE_AUDIO = b"rendered guide"


def renderer(exercise, directory):
    # Rendering is covered in ai_engine; here only the installation.
    return FAKE_AUDIO


@pytest.fixture
def media(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path


def student():
    return User.objects.create_user(username="ana", email="ana@example.com", password="x")


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


def test_exercises_install_as_singing_routines_with_an_exact_reference(media):
    from ai_engine.voice.exercises import EXERCISES, GENERATOR_VERSION
    from ai_engine.voice.reference import decode

    assert singing.install(EXERCISES[:2], renderer=renderer, log=lambda _: None) == 2
    routine = Routine.objects.get(catalog_key="canto-v1-nota-larga")
    assert routine.kind == Routine.Kind.SING
    assert routine.generator == GENERATOR_VERSION
    assert routine.master_video.read() == FAKE_AUDIO
    reference = routine.references.get()
    assert reference.status == RoutineReference.Status.READY
    assert reference.feature_schema == "pitch-reference-v1"
    assert reference.source_sha256 == hashlib.sha256(FAKE_AUDIO).hexdigest()
    artifact = decode(reference.reference_asset.read())
    assert artifact.sha256 == reference.checksum_sha256
    assert artifact.metadata["source_sha256"] == reference.source_sha256
    assert list(artifact.notes) == EXERCISES[0].notes()
    assert reference.scoring_profile["beat_grid"]["bpm"] == EXERCISES[0].bpm
    assert routine.duration_ms == reference.duration_ms


def test_installing_again_changes_nothing_and_new_audio_is_a_new_version(media):
    from ai_engine.voice.exercises import EXERCISES

    quiet = lambda _: None  # noqa: E731
    assert singing.install(EXERCISES[:1], renderer=renderer, log=quiet) == 1
    assert singing.install(EXERCISES[:1], renderer=renderer, log=quiet) == 0
    assert singing.install(EXERCISES[:1], renderer=renderer, refresh=True, log=quiet) == 0
    louder = lambda exercise, directory: b"other guide"  # noqa: E731
    assert singing.install(EXERCISES[:1], renderer=louder, refresh=True, log=quiet) == 1
    routine = Routine.objects.get()
    assert [r.version for r in routine.references.all()] == [2, 1]
    assert routine.master_video.read() == b"other guide"


def test_the_app_lists_dance_and_singing_apart(media):
    from ai_engine.voice.exercises import EXERCISES

    singing.install(EXERCISES[:1], renderer=renderer, log=lambda _: None)
    teacher = User.objects.get(username="catalogo")
    Routine.objects.create(name="Paso básico", instructor=teacher, difficulty="BEGINNER")
    client = client_for(student())

    def names(query=""):
        return {
            (item["name"], item["kind"])
            for item in client.get(f"/api/routines/{query}").json()["results"]
        }

    assert names("?kind=SING") == {("Notas largas", "SING")}
    assert names("?kind=DANCE") == {("Paso básico", "DANCE")}
    assert names() == names("?kind=SING") | names("?kind=DANCE")
    assert names("?kind=OTHER") == names()


def test_an_uploaded_voice_gets_a_melody_version(media, monkeypatch):
    teacher = User.objects.create_user(
        username="profe", email="profe@example.com", role="INSTRUCTOR"
    )
    routine = Routine.objects.create(
        name="Mi canción",
        kind=Routine.Kind.SING,
        instructor=teacher,
        difficulty="BEGINNER",
        master_video=SimpleUploadedFile("voz.m4a", b"voice"),
    )
    monkeypatch.setattr(generate_reference, "delay", Mock())
    reference = queue_reference(routine_id=routine.pk)
    assert (reference.feature_schema, reference.sample_rate_hz) == ("pitch-reference-v1", 31)


def _voice_wav(path, notes=(60, 64, 67, 72, 67, 64, 60), seconds=0.6):
    import numpy as np

    rate = 16000
    parts = []
    for midi in notes:
        t = np.arange(int(seconds * rate)) / rate
        hz = 440.0 * 2 ** ((midi - 69) / 12)
        tone = sum(a * np.sin(2 * np.pi * k * hz * t) for k, a in ((1, 1.0), (2, 0.5), (3, 0.25)))
        parts.append(0.25 * tone * np.minimum(1, np.minimum(t, t[::-1]) / 0.02))
    pcm = (np.concatenate(parts) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())
    return path.read_bytes()


def test_the_worker_turns_a_voice_into_audio_and_melody(media, tmp_path, monkeypatch):
    pytest.importorskip("librosa")
    pytest.importorskip("imageio_ffmpeg")
    from ai_engine.voice.reference import decode

    teacher = User.objects.create_user(
        username="profe", email="profe@example.com", role="INSTRUCTOR"
    )
    voice = _voice_wav(tmp_path / "voz.wav")
    routine = Routine.objects.create(
        name="Arpegio cantado",
        kind=Routine.Kind.SING,
        instructor=teacher,
        difficulty="BEGINNER",
        master_video=SimpleUploadedFile("voz.wav", voice),
    )
    monkeypatch.setattr(generate_reference, "delay", Mock())
    reference = queue_reference(routine_id=routine.pk)
    generate_reference.run(reference.pk)
    reference.refresh_from_db()

    assert reference.status == "READY", reference.processing_error
    assert reference.playback_profile == "app-audio-v1"
    assert reference.playback_video.name.endswith(".m4a")
    assert reference.poster.name == ""
    assert reference.scoring_profile["voice_quality"]["warnings"] == []
    artifact = decode(reference.reference_asset.read())
    assert [note.name for note in artifact.notes] == ["C4", "E4", "G4", "C5", "G4", "E4", "C4"]
    with reference.playback_video.open("rb") as played:
        assert hashlib.sha256(played.read()).hexdigest() == reference.source_sha256
    routine.refresh_from_db()
    assert routine.duration_ms == reference.duration_ms

    client = client_for(teacher)
    audio = client.get(f"/api/routines/{routine.pk}/references/{reference.version}/video/")
    assert audio["Content-Type"] == "audio/mp4"
    assert audio["ETag"] == f'"{reference.source_sha256}"'
    audio.close()


def test_a_recording_without_voice_fails_with_a_clear_message(media, tmp_path, monkeypatch):
    pytest.importorskip("librosa")
    pytest.importorskip("imageio_ffmpeg")
    teacher = User.objects.create_user(
        username="profe", email="profe@example.com", role="INSTRUCTOR"
    )
    silence = tmp_path / "silencio.wav"
    with wave.open(str(silence), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16000)
        out.writeframes(b"\0\0" * 16000 * 3)
    routine = Routine.objects.create(
        name="Nada",
        kind=Routine.Kind.SING,
        instructor=teacher,
        difficulty="BEGINNER",
        master_video=SimpleUploadedFile("silencio.wav", silence.read_bytes()),
    )
    monkeypatch.setattr(generate_reference, "delay", Mock())
    reference = queue_reference(routine_id=routine.pk)
    generate_reference.run(reference.pk)
    reference.refresh_from_db()
    assert reference.status == "FAILED"
    assert reference.processing_error == "No se encontró una voz cantando en la grabación."
    assert reference.playback_video.name == ""


def test_a_singing_routine_is_not_a_task_until_its_practices_sync(media):
    from django.core.exceptions import ValidationError

    from apps.coaching.models import Assignment, Course

    teacher = User.objects.create_user(
        username="profe", email="profe@example.com", role="INSTRUCTOR"
    )
    course = Course.objects.create(name="Coro", instructor=teacher, join_code="CORO2345")
    song = Routine.objects.create(
        name="Canción", kind=Routine.Kind.SING, instructor=teacher, difficulty="BEGINNER"
    )
    dance = Routine.objects.create(name="Paso", instructor=teacher, difficulty="BEGINNER")
    with pytest.raises(ValidationError, match="canto"):
        Assignment(course=course, routine=song).full_clean()
    Assignment(course=course, routine=dance).full_clean()
