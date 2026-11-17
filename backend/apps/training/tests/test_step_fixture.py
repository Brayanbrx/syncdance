"""The phone's upload with per-step results is accepted as is."""

import json

import pytest

from apps.routines.models import RoutineReference
from apps.training.tests.test_summary_sync import (  # noqa: F401  (fixture)
    FIXTURES,
    URL,
    mobile_upload,
)

pytestmark = pytest.mark.django_db


def test_the_phone_fixture_with_steps_is_accepted(mobile_upload):  # noqa: F811
    """`upload_steps_v1.json` is written by the phone (session_sync_test.dart)."""
    client, routine, _ = mobile_upload
    fixture = json.loads((FIXTURES / "upload_steps_v1.json").read_text(encoding="utf-8"))
    profile = fixture.pop("_reference_scoring_profile")
    RoutineReference.objects.filter(routine=routine).update(
        scoring_profile=profile, duration_ms=fixture["duration_ms"]
    )
    fixture.update(routine=routine.pk, reference_version=2)
    response = client.post(URL, fixture, format="json")
    assert response.status_code == 201, response.data
    assert len(response.data["step_results"]) == len(profile["steps"]["items"])
    assert response.data["calibration"] == fixture["calibration"]
