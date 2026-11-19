"""`manage.py seed`: what a fresh platform needs, on every start."""

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from rest_framework.test import APIClient

from apps.accounts.models import User

EMAIL = "jefa@example.com"
PASSWORD = "Escenario-2026"


def seed():
    from io import StringIO

    out = StringIO()
    call_command("seed", stdout=out)
    return out.getvalue()


@pytest.fixture
def configured(settings):
    settings.SEED_ADMIN_EMAIL = EMAIL
    settings.SEED_ADMIN_USERNAME = ""
    settings.SEED_ADMIN_PASSWORD = PASSWORD
    return settings


@pytest.mark.django_db
def test_without_configuration_the_seed_creates_no_account(settings):
    settings.SEED_ADMIN_EMAIL = ""

    assert "SEED_ADMIN_EMAIL vacío" in seed()
    assert not User.objects.exists()


@pytest.mark.django_db
def test_the_superadmin_is_created_once_and_logs_in_with_the_email(configured):
    assert "creado" in seed()

    user = User.objects.get()
    assert (user.username, user.email, user.role) == (EMAIL, EMAIL, User.Role.ADMIN)
    assert user.is_superuser and user.is_staff and user.is_active
    response = APIClient().post(
        "/api/auth/login/", {"username": EMAIL, "password": PASSWORD}, format="json"
    )
    assert response.status_code == 200
    assert (
        APIClient()
        .get("/api/auth/me/", HTTP_AUTHORIZATION=f"Bearer {response.json()['access']}")
        .json()["is_platform_admin"]
    )

    # Every start runs it again: a password changed since then is kept.
    user.set_password("Otra-clave-2027")
    user.save()
    configured.SEED_ADMIN_PASSWORD = "Distinta-2028"
    assert "ya existe" in seed()
    user.refresh_from_db()
    assert user.check_password("Otra-clave-2027")
    assert User.objects.count() == 1


@pytest.mark.django_db
def test_a_chosen_username_is_used(configured):
    configured.SEED_ADMIN_USERNAME = "jefa"

    seed()

    assert User.objects.get().username == "jefa"


@pytest.mark.django_db
def test_an_existing_account_with_that_email_is_never_promoted(configured):
    User.objects.create_user(username="intrusa", email=EMAIL.upper(), password="x")

    assert "no se promueve" in seed()

    user = User.objects.get()
    assert not user.is_superuser and user.role == User.Role.STUDENT


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("password", "message"),
    [("", "SEED_ADMIN_PASSWORD vacío"), ("admin", "SEED_ADMIN_PASSWORD no sirve")],
)
def test_a_missing_or_weak_password_stops_the_start(configured, password, message):
    configured.SEED_ADMIN_PASSWORD = password

    with pytest.raises(CommandError, match=message):
        seed()
    assert not User.objects.exists()
