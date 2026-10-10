import pytest
from django.core.management import CommandError, call_command
from rest_framework.test import APIClient

from apps.accounts.models import User

pytestmark = pytest.mark.django_db


def login(password):
    return APIClient().post(
        "/api/auth/login/", {"username": "admin", "password": password}, format="json"
    )


def test_seed_creates_an_admin_that_can_log_in(settings):
    settings.DEBUG = True
    call_command("seed_admin")
    user = User.objects.get(username="admin")
    assert (user.role, user.is_staff, user.is_superuser) == ("ADMIN", True, True)
    assert login("admin").status_code == 200
    # Idempotent: a second run neither duplicates nor fails.
    call_command("seed_admin")
    assert User.objects.filter(username="admin").count() == 1


def test_existing_password_is_kept_unless_reset(settings):
    settings.DEBUG = True
    User.objects.create_user(username="admin", email="a@example.com", password="otra-clave-1")
    call_command("seed_admin")
    assert login("otra-clave-1").status_code == 200
    call_command("seed_admin", reset_password=True)
    assert login("admin").status_code == 200
    assert User.objects.get(username="admin").is_superuser


def test_seed_refuses_without_debug(settings):
    settings.DEBUG = False
    with pytest.raises(CommandError):
        call_command("seed_admin")
    assert not User.objects.filter(username="admin").exists()
