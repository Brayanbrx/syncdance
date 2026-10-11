import pytest
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession, GameResult
from apps.training.selectors import get_student_progress

pytestmark = pytest.mark.django_db


@pytest.fixture
def sessions():
    teacher = User.objects.create_user(username="profe", email="p@example.com", role="INSTRUCTOR")
    student = User.objects.create_user(username="ana", email="a@example.com")
    routine = Routine.objects.create(name="Primer baile", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        reference_asset="references/demo.json.gz",
        engine_name="fixture",
        checksum_sha256="a" * 64,
        algorithm_version="reference-body-v1",
        duration_ms=10000,
    )

    def session(score, ratio, speed=1.0, game=None):
        now = timezone.now()
        created = DanceSession.objects.create(
            student=student,
            routine=routine,
            reference=reference,
            started_at=now,
            finished_at=now,
            status="COMPLETED",
            pose_score=score,
            quality_ratio=ratio,
            playback_speed=speed,
            reference_version=1,
        )
        if game:
            GameResult.objects.create(session=created, version="dance-game-v2", **game)
        return created

    # 3 of 4 PERFECT: 300/400 = 75 % -> four stars.
    perfect3 = dict(points=300, max_points=400, max_combo=3, perfect=3, great=0, good=0)
    session(80, 0.9, game={**perfect3, "miss": 1, "unrated": 0})
    session(95, 0.9, speed=0.5)  # learn mode: not the normal-speed best
    session(99, 0.2)  # too little coverage to count
    session(None, 0.0)  # no evidence: never a zero
    return student


def test_progress_uses_comparable_practices_and_best_stars(sessions):
    row = get_student_progress()[0]
    assert (row["student__username"], row["routine__name"]) == ("ana", "Primer baile")
    assert (row["practices"], row["games"]) == (4, 1)
    assert row["best_score"] == 80
    assert row["best_stars"] == 4


def test_instructor_pages_in_the_admin(sessions):
    admin_user = User.objects.create_superuser(
        username="admin", email="ad@example.com", password="x"
    )
    client = Client()
    client.force_login(admin_user)
    changelist = reverse("admin:training_dancesession_changelist")
    games = client.get(changelist, {"modo": "juego"})
    assert games.status_code == 200
    assert "★★★★☆" in games.content.decode()
    assert "300/400" in games.content.decode()
    assert "Progreso por alumno" in games.content.decode()
    progress = client.get(reverse("admin:training_dancesession_progress"))
    assert progress.status_code == 200
    page = progress.content.decode()
    assert "ana" in page and "★★★★☆" in page


def test_progress_page_requires_staff(sessions):
    client = Client()
    client.force_login(sessions)  # a student
    response = client.get(reverse("admin:training_dancesession_progress"))
    assert response.status_code == 302


def test_progress_downloads_as_a_spreadsheet(sessions):
    admin_user = User.objects.create_superuser(
        username="admin", email="ad@example.com", password="x"
    )
    # A name a spreadsheet would run as a formula stays plain text.
    sessions.username = "+ana"
    sessions.save()
    client = Client()
    client.force_login(admin_user)
    response = client.get(reverse("admin:training_dancesession_progress_csv"))
    assert response.status_code == 200
    assert response["Content-Type"].startswith("text/csv")
    body = response.content.decode("utf-8")
    assert body.startswith("﻿Alumno;Rutina;Prácticas;Partidas;")
    row = body.splitlines()[1].split(";")
    assert row[:6] == ["'+ana", "Primer baile", "4", "1", "80", "4"]
    progress = client.get(reverse("admin:training_dancesession_progress"))
    assert "Descargar CSV" in progress.content.decode()
