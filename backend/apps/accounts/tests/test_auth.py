import pytest
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle


@pytest.mark.django_db
def test_register_and_login():
    client = APIClient()
    payload = {
        "username": "student01",
        "email": "student@example.com",
        "password": "safe-password-123",
        "accept_terms": True,
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
    payload = {
        "username": "phone",
        "email": "p@example.com",
        "password": "safe-password-123",
        "accept_terms": True,
    }
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


@pytest.mark.django_db
def test_login_attempts_are_throttled_per_account_name():
    client = APIClient()
    wrong = {"username": "Nadie", "password": "not-the-password"}
    statuses = [client.post(reverse("login"), wrong, format="json").status_code for _ in range(11)]
    assert statuses[:10] == [401] * 10
    assert statuses[10] == 429
    # Same name with other spelling: same account, still throttled.
    retry = {"username": " nadie ", "password": "x"}
    assert client.post(reverse("login"), retry, format="json").status_code == 429
    # A classmate behind the same address is not affected.
    other = {"username": "otra", "password": "not-the-password"}
    assert client.post(reverse("login"), other, format="json").status_code == 401
    # A body that is not an object is a bad request, never a server error.
    assert client.post(reverse("login"), [], format="json").status_code == 400
    # Token refresh stays unthrottled: the phone renews access on its own.
    refresh = client.post(reverse("token-refresh"), {"refresh": "x"}, format="json")
    assert refresh.status_code == 401


@pytest.mark.django_db
def test_sign_ups_are_throttled_per_address(monkeypatch):
    monkeypatch.setattr(ScopedRateThrottle, "THROTTLE_RATES", {"register": "2/minute"})
    client = APIClient()

    def sign_up(name):
        payload = {
            "username": name,
            "email": f"{name}@example.com",
            "password": "safe-password-1",
            "accept_terms": True,
        }
        return client.post(reverse("register"), payload, format="json").status_code

    assert [sign_up("a1"), sign_up("a2"), sign_up("a3")] == [201, 201, 429]


@pytest.mark.django_db
@pytest.mark.parametrize("password", ["12345678", "password", "student99x"])
def test_sign_up_rejects_weak_passwords(password):
    payload = {
        "username": "student99",
        "email": "s99@example.com",
        "password": password,
        "accept_terms": True,
    }
    response = APIClient().post(reverse("register"), payload, format="json")
    assert response.status_code == 400
    assert response.data["password"]
