from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.coaching.models import Enrollment, SessionNote

pytestmark = pytest.mark.django_db

COURSES = "/api/coaching/courses/"


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


def test_join_with_a_typed_code_is_idempotent(world):
    luis = world["luis"]
    client = client_for(luis)
    # Typed on a phone: lowercase, a space and a dash still match ABCD2345.
    first = client.post(f"{COURSES}join/", {"code": " abcd-2345 "}, format="json")
    assert first.status_code == 201
    assert first.data["name"] == "Danza 1A"
    assert first.data["instructor"] == "profe"
    assert first.data["joined_at"]
    again = client.post(f"{COURSES}join/", {"code": "ABCD2345"}, format="json")
    assert again.status_code == 200
    assert Enrollment.objects.filter(student=luis).count() == 2


def test_unknown_or_closed_codes_are_rejected(world):
    client = client_for(world["luis"])
    assert client.post(f"{COURSES}join/", {"code": "NOPE0000"}, format="json").status_code == 404
    world["course"].accepts_students = False
    world["course"].save()
    closed = client.post(f"{COURSES}join/", {"code": "ABCD2345"}, format="json")
    assert closed.status_code == 404
    assert not Enrollment.objects.filter(student=world["luis"], course=world["course"]).exists()
    assert client.post(f"{COURSES}join/", {}, format="json").status_code == 400


def test_guessing_codes_is_throttled(world):
    client = client_for(world["luis"])
    statuses = [
        client.post(f"{COURSES}join/", {"code": f"GUESS{i:03d}"}, format="json").status_code
        for i in range(21)
    ]
    assert statuses[-1] == 429
    # Reading progress is never throttled.
    assert client.get(COURSES).status_code == 200


def test_courses_list_only_the_students_own_with_progress(world):
    ana, practice = world["ana"], world["practice"]
    response = client_for(ana).get(COURSES)
    assert response.status_code == 200
    (course,) = response.data["results"]
    assert course["name"] == "Danza 1A"
    (task,) = course["assignments"]
    assert task["routine_name"] == "Paso básico"
    assert task["routine_available"] is True
    # Nothing synced yet: no evidence, not zero stars.
    assert (task["best_stars"], task["practices"], task["completed"]) == (None, 0, False)
    assert task["last_practice_at"] is None

    practice(ana, points=400, speed=0.5)  # learn mode never meets a goal
    practice(ana, points=200)  # 50 % -> 2 stars, below the goal of 3
    task = client_for(ana).get(COURSES).data["results"][0]["assignments"][0]
    assert (task["best_stars"], task["practices"], task["completed"]) == (2, 2, False)
    assert task["last_practice_at"]

    practice(ana, points=300)  # 75 % -> 4 stars
    task = client_for(ana).get(COURSES).data["results"][0]["assignments"][0]
    assert (task["best_stars"], task["completed"], task["overdue"]) == (4, True, False)

    # Luis belongs to another course: Ana's course is not listed for him.
    names = [c["name"] for c in client_for(world["luis"]).get(COURSES).data["results"]]
    assert names == ["Danza 2B"]


def test_an_unmet_assignment_past_its_date_is_overdue(world):
    assignment = world["assignment"]
    assignment.due_date = timezone.localdate() - timedelta(days=1)
    assignment.save()
    task = client_for(world["ana"]).get(COURSES).data["results"][0]["assignments"][0]
    assert (task["completed"], task["overdue"]) == (False, True)


def test_leaving_a_course(world):
    ana, course = world["ana"], world["course"]
    client = client_for(ana)
    assert client.post(f"{COURSES}{course.pk}/leave/").status_code == 204
    assert client.get(COURSES).data["results"] == []
    # Not enrolled any more (or never): nothing to leave.
    assert client.post(f"{COURSES}{course.pk}/leave/").status_code == 404
    assert client.post(f"{COURSES}{world['other_course'].pk}/leave/").status_code == 404


def test_students_read_only_the_notes_on_their_own_practices(world):
    ana_session = world["practice"](world["ana"], points=300)
    luis_session = world["practice"](world["luis"], points=300)
    SessionNote.objects.create(
        session=ana_session, author=world["teacher"], text="¡Bien los brazos!"
    )
    SessionNote.objects.create(
        session=luis_session, author=world["other"], text="Sube las rodillas"
    )
    response = client_for(world["ana"]).get("/api/coaching/notes/")
    assert response.status_code == 200
    (note,) = response.json()["results"]
    assert note["text"] == "¡Bien los brazos!"
    assert note["author"] == "profe"
    assert note["routine_name"] == "Paso básico"
    assert note["session"] == str(ana_session.pk)


def test_coaching_requires_an_account():
    client = APIClient()
    assert client.get(COURSES).status_code == 401
    assert client.get("/api/coaching/notes/").status_code == 401


@pytest.mark.django_db
def test_a_course_lists_the_routines_its_instructor_published(world):
    from apps.routines.models import Routine

    def own(name, **fields):
        return Routine.objects.create(
            name=name,
            instructor=world["teacher"],
            difficulty="BEGINNER",
            visibility=Routine.Visibility.COURSES,
            **fields,
        )

    world["course"].published_routines.add(
        own("Publicada", style="Urbano"),
        own("Borrador", published_at=None),
        own("Inactiva", is_active=False),
    )
    world["routine"].published_at = None  # the assigned routine went back to draft
    world["routine"].save()

    course = client_for(world["ana"]).get("/api/coaching/courses/").json()["results"][0]

    assert [r["name"] for r in course["routines"]] == ["Publicada"]
    assert course["routines"][0]["style"] == "Urbano"
    assert course["assignments"][0]["routine_available"] is False
