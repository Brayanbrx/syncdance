"""Production settings: Django's deployment checklist, run as in the image."""

import os
import secrets
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent


def deploy_check(**env):
    environment = {key: value for key, value in os.environ.items() if not key.startswith("DJANGO_")}
    environment.update(DJANGO_SETTINGS_MODULE="config.settings.production", **env)
    return subprocess.run(
        [sys.executable, "manage.py", "check", "--deploy", "--fail-level", "WARNING"],
        cwd=BACKEND,
        env=environment,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_production_settings_pass_the_deployment_checklist():
    result = deploy_check(
        DJANGO_SECRET_KEY=secrets.token_urlsafe(50),
        DJANGO_ALLOWED_HOSTS="syncdance.example.com",
        DJANGO_CSRF_TRUSTED_ORIGINS="https://syncdance.example.com",
        LEGAL_CONTACT_EMAIL="privacidad@syncdance.example.com",
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_production_refuses_to_start_without_a_real_secret_key():
    missing = deploy_check(DJANGO_ALLOWED_HOSTS="syncdance.example.com")
    sample = deploy_check(
        DJANGO_SECRET_KEY="change-me", DJANGO_ALLOWED_HOSTS="syncdance.example.com"
    )

    for result in (missing, sample):
        assert result.returncode != 0
        assert "DJANGO_SECRET_KEY" in result.stderr
