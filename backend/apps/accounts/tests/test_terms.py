import pytest
from django.core.checks import run_checks
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import User

SIGN_UP = {"username": "ana", "email": "ana@example.com", "password": "safe-password-123"}


@pytest.mark.django_db
@pytest.mark.parametrize("accepted", [None, False])
def test_an_account_needs_the_terms_accepted(accepted):
    payload = SIGN_UP if accepted is None else {**SIGN_UP, "accept_terms": accepted}

    response = APIClient().post(reverse("register"), payload, format="json")

    assert response.status_code == 400
    assert "accept_terms" in response.json()
    assert not User.objects.exists()


@pytest.mark.django_db
def test_the_accepted_version_and_moment_are_kept(settings):
    settings.LEGAL_TERMS_VERSION = "2026-11-16"

    response = APIClient().post(
        reverse("register"), {**SIGN_UP, "accept_terms": True}, format="json"
    )

    assert response.status_code == 201
    user = User.objects.get(username="ana")
    assert user.terms_version == "2026-11-16"
    assert user.terms_accepted_at is not None
    assert user.role == User.Role.STUDENT


@pytest.mark.django_db
def test_the_pages_read_who_is_responsible_and_the_version(settings):
    settings.LEGAL_CONTROLLER = "Academia Ejemplo"
    settings.LEGAL_CONTACT_EMAIL = "privacidad@example.com"
    settings.LEGAL_TERMS_VERSION = "2026-11-16"

    response = APIClient(HTTP_AUTHORIZATION="Bearer stale").get(reverse("legal"))

    assert response.status_code == 200
    assert response.json() == {
        "controller": "Academia Ejemplo",
        "contact_email": "privacidad@example.com",
        "terms_version": "2026-11-16",
    }


def test_a_deployment_without_a_contact_email_is_flagged(settings):
    def deploy_warnings():
        return {message.id for message in run_checks(include_deployment_checks=True)}

    settings.LEGAL_CONTACT_EMAIL = ""
    missing = deploy_warnings()
    settings.LEGAL_CONTACT_EMAIL = "privacidad@example.com"
    present = deploy_warnings()

    assert "accounts.W001" in missing
    assert "accounts.W001" not in present
    assert "accounts.W001" not in {message.id for message in run_checks()}
