import pytest
from django.urls import reverse
from rest_framework.test import APIClient


@pytest.mark.django_db
def test_register_and_login():
    client = APIClient()
    payload = {
        "username": "student01",
        "email": "student@example.com",
        "password": "safe-password-123",
    }

    register_response = client.post(reverse("register"), payload, format="json")
    login_response = client.post(
        reverse("login"),
        {"username": payload["username"], "password": payload["password"]},
        format="json",
    )

    assert register_response.status_code == 201
    assert login_response.status_code == 200
    assert "access" in login_response.data


@pytest.mark.django_db
def test_refresh_rotates_and_logout_revokes_the_phone_session():
    client = APIClient()
    payload = {"username": "phone", "email": "p@example.com", "password": "safe-password-123"}
    client.post(reverse("register"), payload, format="json")
    tokens = client.post(
        reverse("login"),
        {"username": "phone", "password": payload["password"]},
        format="json",
    ).data
    rotated = client.post(reverse("token-refresh"), {"refresh": tokens["refresh"]}, format="json")
    assert rotated.status_code == 200
    assert rotated.data["refresh"] != tokens["refresh"]
    # A used refresh token cannot be replayed.
    replay = client.post(reverse("token-refresh"), {"refresh": tokens["refresh"]}, format="json")
    assert replay.status_code == 401
    logout = client.post(reverse("logout"), {"refresh": rotated.data["refresh"]}, format="json")
    assert logout.status_code == 200
    after = client.post(
        reverse("token-refresh"), {"refresh": rotated.data["refresh"]}, format="json"
    )
    assert after.status_code == 401
