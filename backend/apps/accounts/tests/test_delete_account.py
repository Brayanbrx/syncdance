import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Course, Enrollment, SessionNote
from apps.performances.models import Performance
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession

PASSWORD = "safe-password-123"


@pytest.fixture
def media(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    return tmp_path


@pytest.fixture
def school(db):
    teacher = User.objects.create_user(
        username="profe", email="p@example.com", password=PASSWORD, role="INSTRUCTOR"
    )
    ana = User.objects.create_user(username="ana", email="a@example.com", password=PASSWORD)
    routine = Routine.objects.create(name="Paso", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference.objects.create(
        routine=routine, version=1, status="READY", duration_ms=10000
    )
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    Enrollment.objects.create(course=course, student=ana)
    now = timezone.now()
    session = DanceSession.objects.create(
        student=ana,
        routine=routine,
        reference=reference,
        started_at=now,
        finished_at=now,
        status="COMPLETED",
        reference_version=1,
    )
    SessionNote.objects.create(session=session, author=teacher, text="Brazos más altos")
    return {"teacher": teacher, "ana": ana, "routine": routine, "course": course}


def signed_in(username):
    client = APIClient()
    tokens = client.post(
        reverse("login"), {"username": username, "password": PASSWORD}, format="json"
    ).json()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    return client, tokens


def delete(client, password=PASSWORD):
    return client.post(reverse("delete-account"), {"password": password}, format="json")


@pytest.mark.django_db
def test_a_student_deletes_the_account_and_everything_only_theirs(
    school, media, django_capture_on_commit_callbacks
):
    ana = school["ana"]
    video = Performance.objects.create(
        student=ana,
        routine=school["routine"],
        video=SimpleUploadedFile("baile.mp4", b"video", content_type="video/mp4"),
    ).video
    stored = media / video.name
    assert stored.exists()
    client, tokens = signed_in("ana")

    # Files are removed only after the deletion commits.
    with django_capture_on_commit_callbacks(execute=True):
        response = delete(client)

    assert response.status_code == 204
    assert not User.objects.filter(pk=ana.pk).exists()
    assert not DanceSession.objects.exists()
    assert not Enrollment.objects.exists()
    assert not SessionNote.objects.exists()  # notes about her practices
    assert not stored.exists()
    # The instructor and the course stay.
    assert Course.objects.filter(pk=school["course"].pk).exists()
    anonymous = APIClient()
    refresh = anonymous.post(
        reverse("token-refresh"), {"refresh": tokens["refresh"]}, format="json"
    )
    login = anonymous.post(
        reverse("login"), {"username": "ana", "password": PASSWORD}, format="json"
    )
    assert refresh.status_code == 401
    assert login.status_code == 401


@pytest.mark.django_db
def test_a_wrong_password_deletes_nothing(school):
    client, _ = signed_in("ana")

    response = delete(client, "not-my-password")

    assert response.status_code == 400
    assert response.json() == {"password": ["La contraseña no es correcta."]}
    assert User.objects.filter(username="ana").exists()


@pytest.mark.django_db
def test_an_instructor_with_courses_must_hand_them_over_first(school):
    client, _ = signed_in("profe")

    response = delete(client)

    assert response.status_code == 409
    assert "Pide a un administrador" in response.json()["detail"]
    assert User.objects.filter(username="profe").exists()


@pytest.mark.django_db
def test_an_instructor_without_content_can_leave(db):
    User.objects.create_user(
        username="nuevo", email="n@example.com", password=PASSWORD, role="INSTRUCTOR"
    )
    client, _ = signed_in("nuevo")

    assert delete(client).status_code == 204
    assert not User.objects.filter(username="nuevo").exists()


@pytest.mark.django_db
def test_a_superuser_cannot_delete_itself(db):
    User.objects.create_superuser(username="root", email="r@example.com", password=PASSWORD)
    client, _ = signed_in("root")

    response = delete(client)

    assert response.status_code == 409
    assert "superusuario" in response.json()["detail"]


@pytest.mark.django_db
def test_deleting_needs_a_signed_in_account(db):
    assert delete(APIClient()).status_code == 401
