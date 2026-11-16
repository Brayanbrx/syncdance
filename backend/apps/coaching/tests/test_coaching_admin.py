import pytest
from django.core.exceptions import ValidationError
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.coaching.models import Course, SessionNote

pytestmark = pytest.mark.django_db


def admin_client(user):
    client = Client()
    client.force_login(user)
    return client


def test_the_instructor_role_opens_the_admin(world):
    assert world["teacher"].is_staff
    assert not world["ana"].is_staff
    promoted = world["luis"]
    promoted.role = User.Role.INSTRUCTOR
    promoted.save(update_fields=["role"])
    promoted.refresh_from_db()
    assert promoted.is_staff


def test_instructors_manage_only_their_own_courses(world):
    client = admin_client(world["teacher"])
    listing = client.get(reverse("admin:coaching_course_changelist"))
    assert listing.status_code == 200
    page = listing.content.decode()
    assert "Danza 1A" in page and "ABCD2345" in page
    assert "Danza 2B" not in page
    other = reverse("admin:coaching_course_change", args=[world["other_course"].pk])
    assert client.get(other).status_code in (302, 403, 404)
    progress = reverse("admin:coaching_course_progress", args=[world["other_course"].pk])
    assert client.get(progress).status_code == 404


def test_a_new_course_belongs_to_the_instructor_who_creates_it(world):
    client = admin_client(world["teacher"])
    response = client.post(
        reverse("admin:coaching_course_add"),
        {
            "name": "Danza 3C",
            "accepts_students": "on",
            "assignments-TOTAL_FORMS": "1",
            "assignments-INITIAL_FORMS": "0",
            "assignments-0-routine": str(world["routine"].pk),
            "assignments-0-target_stars": "4",
            "assignments-0-due_date": "",
            "assignments-0-instructions": "Practica con espejo",
            "enrollments-TOTAL_FORMS": "0",
            "enrollments-INITIAL_FORMS": "0",
        },
    )
    assert response.status_code == 302, response.content.decode()[:2000]
    course = Course.objects.get(name="Danza 3C")
    assert course.instructor == world["teacher"]
    assert len(course.join_code) == 8
    assert course.assignments.get().target_stars == 4


def test_course_progress_shows_each_student_against_the_goal(world):
    world["practice"](world["ana"], points=300)  # 4 stars, goal 3
    client = admin_client(world["teacher"])
    response = client.get(reverse("admin:coaching_course_progress", args=[world["course"].pk]))
    assert response.status_code == 200
    page = response.content.decode()
    assert "ana" in page and "★★★★☆" in page and "✓" in page and "1/1" in page
    assert "luis" not in page


def test_instructors_review_only_their_students_sessions(world):
    ana_session = world["practice"](world["ana"], points=300)
    luis_session = world["practice"](world["luis"], points=300)
    client = admin_client(world["teacher"])
    listing = client.get(reverse("admin:training_dancesession_changelist"))
    assert listing.status_code == 200
    assert "ana" in listing.content.decode()
    assert "luis" not in listing.content.decode()
    own = client.get(reverse("admin:training_dancesession_change", args=[ana_session.pk]))
    assert own.status_code == 200
    assert "300/400" in own.content.decode() or "300" in own.content.decode()
    foreign = reverse("admin:training_dancesession_change", args=[luis_session.pk])
    assert client.get(foreign).status_code in (302, 403, 404)
    progress = client.get(reverse("admin:training_dancesession_progress")).content.decode()
    assert "ana" in progress and "luis" not in progress
    csv = client.get(reverse("admin:training_dancesession_progress_csv")).content.decode()
    assert "ana" in csv and "luis" not in csv


def test_the_instructor_writes_an_observation_on_a_practice(world):
    session = world["practice"](world["ana"], points=300)
    client = admin_client(world["teacher"])
    url = reverse("admin:training_dancesession_change", args=[session.pk])
    form = {
        "instructor_notes-TOTAL_FORMS": "1",
        "instructor_notes-INITIAL_FORMS": "0",
        "instructor_notes-0-text": "Muy bien, ahora sube los brazos al final.",
    }
    # The read-only result inlines post their empty management forms too.
    for prefix in (
        "game",
        "timeline_segments",
        "feedback_counts",
        "segment_scores",
        "error_events",
    ):
        form[f"{prefix}-TOTAL_FORMS"] = "0"
        form[f"{prefix}-INITIAL_FORMS"] = "0"
    form["game-TOTAL_FORMS"] = "1"
    form["game-INITIAL_FORMS"] = "1"
    form["game-0-id"] = str(session.game.pk)
    form["game-0-session"] = str(session.pk)
    response = client.post(url, form)
    assert response.status_code == 302, response.content.decode()[:3000]
    note = SessionNote.objects.get(session=session)
    assert note.author == world["teacher"]
    assert note.text.startswith("Muy bien")


def test_instructors_cannot_delete_sessions(world):
    session = world["practice"](world["ana"], points=300)
    client = admin_client(world["teacher"])
    url = reverse("admin:training_dancesession_delete", args=[session.pk])
    assert client.get(url).status_code in (302, 403)


def test_notes_only_on_students_of_ones_courses(world):
    luis_session = world["practice"](world["luis"], points=300)
    note = SessionNote(session=luis_session, author=world["teacher"], text="Hola")
    with pytest.raises(ValidationError):
        note.full_clean()
    SessionNote(session=luis_session, author=world["other"], text="Bien").full_clean()


def test_students_do_not_reach_the_courses_admin(world):
    client = admin_client(world["ana"])
    response = client.get(reverse("admin:coaching_course_changelist"))
    assert response.status_code == 302
