import re
from urllib.parse import parse_qs, urlparse

import pytest
from django.core import mail
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import User

PASSWORD = "safe-password-123"
NEW_PASSWORD = "another-safe-pass-456"


@pytest.fixture
def student(db):
    return User.objects.create_user(
        username="ana", email="ana@example.com", password=PASSWORD, first_name="Ana"
    )


def ask(client, email):
    return client.post(reverse("password-reset"), {"email": email}, format="json")


def link_params():
    link = re.search(r"https?://\S+", mail.outbox[-1].body).group(0)
    query = parse_qs(urlparse(link).query)
    return link, query["uid"][0], query["token"][0]


def confirm(client, uid, token, password=NEW_PASSWORD):
    return client.post(
        reverse("password-reset-confirm"),
        {"uid": uid, "token": token, "new_password": password},
        format="json",
    )


def login(client, password):
    return client.post(reverse("login"), {"username": "ana", "password": password}, format="json")


@pytest.mark.django_db
def test_the_link_goes_to_the_web_page_of_the_account(student, settings):
    settings.PUBLIC_WEB_URL = "https://syncdance.example"

    response = ask(APIClient(), "ANA@example.com ")

    assert response.status_code == 202
    assert len(mail.outbox) == 1
    message = mail.outbox[0]
    assert message.to == ["ana@example.com"]
    assert "usuario ana" in message.body
    link, _, _ = link_params()
    assert link.startswith("https://syncdance.example/cuenta/restablecer?uid=")


@pytest.mark.django_db
@pytest.mark.parametrize("email", ["nadie@example.com", "ana@example.com"])
def test_the_answer_never_reveals_whether_an_address_exists(student, email):
    student.is_active = email != "ana@example.com"  # inactive: no mail either
    student.save()

    response = ask(APIClient(), email)

    assert response.status_code == 202
    assert response.json()["detail"].startswith("Si existe una cuenta")
    assert mail.outbox == []


@pytest.mark.django_db
def test_the_new_password_works_once_and_closes_open_sessions(student):
    client = APIClient()
    session = login(client, PASSWORD).json()
    rotated = client.post(
        reverse("token-refresh"), {"refresh": session["refresh"]}, format="json"
    ).json()
    ask(client, "ana@example.com")
    _, uid, token = link_params()

    response = confirm(client, uid, token)
    again = confirm(client, uid, token, "yet-another-pass-789")

    assert response.status_code == 200
    assert login(client, PASSWORD).status_code == 401
    assert login(client, NEW_PASSWORD).status_code == 200
    # The phone's saved session (already rotated once) no longer renews.
    refresh = client.post(reverse("token-refresh"), {"refresh": rotated["refresh"]}, format="json")
    assert refresh.status_code == 401
    assert again.status_code == 400
    assert "token" in again.json()


@pytest.mark.django_db
def test_a_weak_password_is_refused_and_the_link_stays_usable(student):
    client = APIClient()
    ask(client, "ana@example.com")
    _, uid, token = link_params()

    weak = confirm(client, uid, token, "12345678")
    good = confirm(client, uid, token)

    assert weak.status_code == 400
    assert "new_password" in weak.json()
    assert good.status_code == 200


@pytest.mark.django_db
@pytest.mark.parametrize("uid", ["", "not-base64!", "MTIzNDU2"])  # MTIzNDU2 = pk 123456
def test_a_broken_link_is_refused(student, uid):
    response = confirm(APIClient(), uid or "x", "some-token")

    assert response.status_code == 400
    assert response.json()["token"] == ["El enlace no es válido o ya venció. Pide uno nuevo."]
    student.refresh_from_db()
    assert student.check_password(PASSWORD)


@pytest.mark.django_db
def test_one_mailbox_gets_at_most_five_links_an_hour(student):
    client = APIClient()

    answers = [ask(client, "ana@example.com").status_code for _ in range(6)]
    other = ask(client, "otra@example.com")

    assert answers == [202] * 5 + [429]
    assert len(mail.outbox) == 5
    assert other.status_code == 202


@pytest.mark.django_db
def test_a_mail_server_failure_does_not_change_the_answer(student, monkeypatch):
    from smtplib import SMTPException

    def broken(*args, **kwargs):
        raise SMTPException("server down")

    monkeypatch.setattr("apps.accounts.services.send_mail", broken)

    response = ask(APIClient(), "ana@example.com")

    assert response.status_code == 202
    assert response.json()["detail"].startswith("Si existe una cuenta")
