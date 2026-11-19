"""Mail through Brevo's API (common/mail.py) and how the settings pick it."""

import io
import json
import os
import secrets
import subprocess
import sys
import urllib.error
from pathlib import Path

import pytest
from django.core.mail import EmailMultiAlternatives, get_connection

from common.mail import BREVO_URL, MailRejected

BACKEND = Path(__file__).resolve().parent.parent
BREVO = "common.mail.BrevoEmailBackend"


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


@pytest.fixture
def brevo(monkeypatch):
    """Requests that would reach Brevo, and what Brevo answers."""
    sent = []
    answer = {"error": None}

    def urlopen(request, timeout):
        sent.append(
            {
                "url": request.full_url,
                "method": request.get_method(),
                "key": request.get_header("Api-key"),
                "timeout": timeout,
                "body": json.loads(request.data),
            }
        )
        if answer["error"] is not None:
            code, body = answer["error"]
            raise urllib.error.HTTPError(
                request.full_url, code, "error", {}, io.BytesIO(json.dumps(body).encode())
            )
        return FakeResponse(b'{"messageId": "<abc@smtp-relay.mailin.fr>"}')

    monkeypatch.setattr("common.mail.urllib.request.urlopen", urlopen)
    return {"sent": sent, "answer": answer}


def test_a_message_goes_to_brevo_with_text_and_html(brevo):
    message = EmailMultiAlternatives(
        subject="Hola",
        body="Texto",
        from_email='"SYNCDANCE" <syncdance@example.com>',
        to=["Ana <ana@example.com>", "luis@example.com"],
        reply_to=["soporte@example.com"],
        connection=get_connection(BREVO, api_key="clave-de-prueba"),
    )
    message.attach_alternative("<p>Texto</p>", "text/html")

    assert message.send() == 1

    [request] = brevo["sent"]
    assert (request["url"], request["method"]) == (BREVO_URL, "POST")
    assert request["key"] == "clave-de-prueba"
    assert request["timeout"] == 10
    assert request["body"] == {
        "sender": {"email": "syncdance@example.com", "name": "SYNCDANCE"},
        "to": [{"email": "ana@example.com", "name": "Ana"}, {"email": "luis@example.com"}],
        "replyTo": {"email": "soporte@example.com"},
        "subject": "Hola",
        "textContent": "Texto",
        "htmlContent": "<p>Texto</p>",
    }


@pytest.mark.django_db
def test_the_password_reset_mail_leaves_through_brevo(brevo, settings):
    from apps.accounts.models import User
    from apps.accounts.services import send_password_reset_email

    settings.EMAIL_BACKEND = BREVO
    settings.BREVO_API_KEY = "clave"
    settings.DEFAULT_FROM_EMAIL = '"SYNCDANCE" <syncdance@example.com>'
    user = User.objects.create_user(username="ana", email="ana@example.com", password="x")

    send_password_reset_email(user)

    [request] = brevo["sent"]
    assert request["body"]["sender"] == {"email": "syncdance@example.com", "name": "SYNCDANCE"}
    assert request["body"]["to"] == [{"email": "ana@example.com"}]
    assert "/cuenta/restablecer?uid=" in request["body"]["textContent"]


def test_a_refusal_is_not_retried_and_an_outage_is(brevo):
    connection = get_connection(BREVO, api_key="mala")
    message = EmailMultiAlternatives("Hola", "Texto", "a@example.com", ["b@example.com"])

    brevo["answer"]["error"] = (401, {"code": "unauthorized", "message": "Key not found"})
    with pytest.raises(MailRejected, match="401.*unauthorized: Key not found") as refused:
        connection.send_messages([message])
    assert not isinstance(refused.value, OSError)  # the reset task does not retry it
    assert "mala" not in str(refused.value)

    brevo["answer"]["error"] = (503, {})
    with pytest.raises(OSError):  # the reset task retries this one
        connection.send_messages([message])

    quiet = get_connection(BREVO, api_key="mala", fail_silently=True)
    assert quiet.send_messages([message]) == 0


def settings_in_production(**env):
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("DJANGO_", "MAIL_", "BREVO_"))
    }
    environment.update(
        DJANGO_SETTINGS_MODULE="config.settings.production",
        DJANGO_SECRET_KEY=secrets.token_urlsafe(50),
        DJANGO_ALLOWED_HOSTS="syncdance.example.com",
        **env,
    )
    return subprocess.run(
        [
            sys.executable,
            "manage.py",
            "shell",
            "-c",
            "from django.conf import settings; "
            "print(settings.EMAIL_BACKEND); print(settings.DEFAULT_FROM_EMAIL)",
        ],
        cwd=BACKEND,
        env=environment,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_production_sends_through_brevo_when_it_is_the_provider():
    result = settings_in_production(
        MAIL_PROVIDER="brevo",
        MAIL_FROM="syncdance@example.com",
        MAIL_FROM_NAME="SYNCDANCE",
        BREVO_API_KEY="xkeysib-prueba",
        # A leftover console backend does not win over the chosen provider.
        DJANGO_EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()  # the shell may also report its imports
    assert BREVO in lines
    assert '"SYNCDANCE" <syncdance@example.com>' in lines


def test_production_refuses_brevo_without_a_key_or_an_unknown_provider():
    missing = settings_in_production(MAIL_PROVIDER="brevo", MAIL_FROM="syncdance@example.com")
    unknown = settings_in_production(MAIL_PROVIDER="sendgrid")

    assert missing.returncode != 0
    assert "BREVO_API_KEY" in missing.stderr
    assert unknown.returncode != 0
    assert "MAIL_PROVIDER=sendgrid" in unknown.stderr
