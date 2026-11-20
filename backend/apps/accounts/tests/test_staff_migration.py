import importlib

import pytest
from django.apps import apps
from django.test import Client

from apps.accounts.models import User

pytestmark = pytest.mark.django_db

migration = importlib.import_module("apps.accounts.migrations.0003_staff_for_instructors")


def test_old_instructors_can_open_the_admin_with_their_password():
    teacher = User.objects.create_user(
        username="profe", email="p@example.com", password="clave-segura-1", role="INSTRUCTOR"
    )
    student = User.objects.create_user(username="ana", email="a@example.com", password="x")
    # An account saved before the role set `is_staff` (or written with update()).
    User.objects.filter(pk=teacher.pk).update(is_staff=False)
    client = Client()
    credentials = {"username": "profe", "password": "clave-segura-1"}
    # Refused: the Admin shows the login form again instead of redirecting.
    assert client.post("/admin/login/", credentials).status_code == 200

    migration.staff_for_instructors(apps, None)

    teacher.refresh_from_db()
    student.refresh_from_db()
    assert teacher.is_staff and not student.is_staff
    response = client.post(
        "/admin/login/?next=/admin/coaching/course/",
        {**credentials, "next": "/admin/coaching/course/"},
    )
    assert response.status_code == 302
    assert response["Location"] == "/admin/coaching/course/"
    assert client.get("/admin/coaching/course/").status_code == 200
