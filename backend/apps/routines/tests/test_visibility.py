"""Who sees which routine: the catalog, course routines and drafts."""

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.coaching.models import Assignment, Course, Enrollment
from apps.routines.models import Routine

COURSES = Routine.Visibility.COURSES


@pytest.fixture
def school(db):
    def person(name, role="STUDENT"):
        return User.objects.create_user(
            username=name, email=f"{name}@example.com", password="x", role=role
        )

    admin, teacher, other = (
        person("admin", "ADMIN"),
        person("profe", "INSTRUCTOR"),
        person("otra", "INSTRUCTOR"),
    )
    ana, luis = person("ana"), person("luis")
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    other_course = Course.objects.create(name="Danza 2B", instructor=other, join_code="WXYZ6789")
    Enrollment.objects.create(course=course, student=ana)

    def routine(name, owner, **fields):
        return Routine.objects.create(name=name, instructor=owner, difficulty="BEGINNER", **fields)

    routine("Catálogo", admin)
    routine("Catálogo en borrador", admin, published_at=None)
    routine("Catálogo inactiva", admin, is_active=False)
    course.published_routines.add(routine("Del curso", teacher, visibility=COURSES))
    Assignment.objects.create(
        course=course,
        routine=routine("Tarea del curso", teacher, visibility=COURSES),
        target_stars=3,
        due_date=timezone.localdate(),
    )
    routine("Privada del profe", teacher, visibility=COURSES)
    course.published_routines.add(
        routine("Borrador en el curso", teacher, visibility=COURSES, published_at=None)
    )
    other_course.published_routines.add(routine("De otro curso", other, visibility=COURSES))
    return {"ana": ana, "luis": luis, "teacher": teacher, "admin": admin, "course": course}


def names_seen_by(user):
    client = APIClient()
    client.force_authenticate(user)
    response = client.get("/api/routines/", {"page_size": 100})
    assert response.status_code == 200
    return sorted(item["name"] for item in response.json()["results"])


@pytest.mark.django_db
def test_a_student_sees_the_catalog_and_the_routines_of_their_courses(school):
    assert names_seen_by(school["ana"]) == ["Catálogo", "Del curso", "Tarea del curso"]
    assert names_seen_by(school["luis"]) == ["Catálogo"]


@pytest.mark.django_db
def test_leaving_the_course_hides_its_routines(school):
    Enrollment.objects.filter(student=school["ana"]).delete()

    assert names_seen_by(school["ana"]) == ["Catálogo"]


@pytest.mark.django_db
def test_hidden_routines_cannot_be_downloaded_by_id(school):
    client = APIClient()
    client.force_authenticate(school["luis"])

    for name in ["Del curso", "Privada del profe", "Catálogo en borrador", "De otro curso"]:
        routine = Routine.objects.get(name=name)
        for path in ("", "reference/", "reference/status/"):
            response = client.get(f"/api/routines/{routine.pk}/{path}")
            assert response.status_code == 404, (name, path)


@pytest.mark.django_db
def test_an_instructor_sees_all_of_their_own_routines_drafts_included(school):
    assert names_seen_by(school["teacher"]) == [
        "Borrador en el curso",
        "Del curso",
        "Privada del profe",
        "Tarea del curso",
    ]


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("owner", "visibility", "published"),
    [("teacher", "COURSES", False), ("admin", "CATALOG", True)],
)
def test_new_routines_start_as_drafts_only_for_instructors(school, owner, visibility, published):
    client = APIClient()
    client.force_authenticate(school[owner])

    response = client.post(
        "/api/routines/", {"name": "Nueva", "difficulty": "BEGINNER"}, format="json"
    )

    assert response.status_code == 201
    routine = Routine.objects.get(name="Nueva")
    assert routine.visibility == visibility
    assert routine.is_published is published


@pytest.mark.django_db
def test_an_instructor_can_only_offer_the_catalog_and_their_own_routines(school):
    from apps.coaching.admin import assignable_routines

    offered = sorted(r.name for r in assignable_routines(school["teacher"]))
    everything = sorted(r.name for r in assignable_routines(school["admin"]))

    assert offered == [
        "Borrador en el curso",
        "Catálogo",
        "Del curso",
        "Privada del profe",
        "Tarea del curso",
    ]
    assert "De otro curso" in everything
    assert "Catálogo en borrador" in everything
