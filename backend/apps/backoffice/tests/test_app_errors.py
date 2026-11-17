"""Errors the Android app reports: grouped, cut to size, throttled."""

import pytest
from django.core.cache import cache
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle

from apps.backoffice.models import AppErrorReport

pytestmark = pytest.mark.django_db
URL = "/api/app/errors/"
STACK = "\n".join(
    [
        "#0      SessionStore.save (package:syncdance_mobile/session_store.dart:80)",
        "#1      _DanceGameScreenState._finish (package:syncdance_mobile/game.dart:312)",
        "#2      <asynchronous suspension>",
    ]
)


@pytest.fixture(autouse=True)
def fresh_throttle():
    cache.clear()


def report(**changes):
    payload = {
        "app_version": "1.1.0+2",
        "os_version": "Android 13",
        "kind": "FileSystemException",
        "message": "Resumen demasiado grande.",
        "stack": STACK,
        **changes,
    }
    return APIClient().post(URL, payload, format="json")


def test_the_same_error_is_counted_not_repeated():
    assert report().status_code == 204
    assert report(message="otro texto, mismo lugar").status_code == 204
    assert report(app_version="1.2.0+3").status_code == 204  # a new version is a new row

    first = AppErrorReport.objects.get(app_version="1.1.0+2")
    assert first.count == 2
    assert first.kind == "FileSystemException"
    assert first.message == "Resumen demasiado grande."
    assert AppErrorReport.objects.count() == 2


def test_long_fields_are_cut_and_bad_reports_refused():
    assert report(message="x" * 5000, stack="y" * 9000).status_code == 204
    saved = AppErrorReport.objects.get()
    assert (len(saved.message), len(saved.stack)) == (500, 4000)
    assert report(kind="").status_code == 400
    assert report(app_version="v" * 41).status_code == 400


def test_a_crash_loop_is_throttled(monkeypatch):
    monkeypatch.setattr(ScopedRateThrottle, "THROTTLE_RATES", {"app_errors": "2/hour"})
    assert [report().status_code for _ in range(3)] == [204, 204, 429]
