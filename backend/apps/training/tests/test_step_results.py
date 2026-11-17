"""Per-step results (`step-summary-v1`) and calibration tries in the upload."""

import pytest

from apps.routines.models import RoutineReference
from apps.training.models import DanceSession
from apps.training.tests.test_summary_sync import (  # noqa: F401  (fixture)
    URL,
    mobile_upload,
)

pytestmark = pytest.mark.django_db

STEPS = [
    {"name": "Entrada", "start_ms": 0, "end_ms": 5000, "counts": 8, "tip": ""},
    {"name": "Giro", "start_ms": 5000, "end_ms": 10000, "counts": 8, "tip": ""},
]


@pytest.fixture
def with_steps(mobile_upload):  # noqa: F811
    client, routine, payload = mobile_upload
    RoutineReference.objects.filter(routine=routine).update(
        scoring_profile={"steps": {"version": "routine-steps-v1", "items": STEPS}}
    )
    payload.update(
        step_summary_version="step-summary-v1",
        step_results=[
            {
                "index": 0,
                "start_ms": 0,
                "end_ms": 5000,
                "evaluated_ms": 4000,
                "score": 80.0,
                "feedback": {"leftElbow_extend": 2},
            },
            {"index": 1, "start_ms": 5000, "end_ms": 10000, "evaluated_ms": 5000, "score": 70.0},
        ],
        calibration={"attempts": 3, "calibrated": 2},
    )
    return client, routine, payload


def test_step_results_and_calibration_are_stored_and_returned(with_steps):
    client, _, payload = with_steps
    response = client.post(URL, payload, format="json")
    assert response.status_code == 201, response.data
    session = DanceSession.objects.get()
    assert session.step_summary_version == "step-summary-v1"
    assert [(s.index, s.score, s.feedback) for s in session.step_results.all()] == [
        (0, 80.0, {"leftElbow_extend": 2}),
        (1, 70.0, {}),
    ]
    assert (session.calibration_attempts, session.calibration_successes) == (3, 2)
    listed = client.get(URL).json()["results"][0]
    assert listed["step_results"][1]["evaluated_ms"] == 5000
    assert listed["calibration"] == {"attempts": 3, "calibrated": 2}


def test_an_app_without_steps_still_uploads(with_steps):
    client, _, payload = with_steps
    for key in ("step_summary_version", "step_results", "calibration"):
        payload.pop(key)
    response = client.post(URL, payload, format="json")
    assert response.status_code == 201, response.data
    assert response.data["step_results"] == []
    assert response.data["calibration"] is None


def change(payload, index, **values):
    payload["step_results"][index].update(values)
    return payload


@pytest.mark.parametrize(
    "spoil",
    [
        lambda p: p.update(step_summary_version="step-summary-v9"),
        lambda p: p["step_results"].pop(),  # fewer than the reference has
        lambda p: change(p, 1, start_ms=4000),  # not the published window
        lambda p: change(p, 1, evaluated_ms=0),  # score without evidence
        lambda p: change(p, 0, evaluated_ms=5000, score=80.0),  # more than evaluated
        lambda p: change(p, 0, feedback={"rightKnee_bend": 1}),  # unknown cue
        lambda p: change(p, 0, feedback={"leftElbow_extend": 4}),  # more than shown
        lambda p: p.update(calibration={"attempts": 1, "calibrated": 2}),
    ],
)
def test_impossible_step_results_are_refused_without_partial_rows(with_steps, spoil):
    client, _, payload = with_steps
    spoil(payload)
    response = client.post(URL, payload, format="json")
    assert response.status_code == 400, response.data
    assert not DanceSession.objects.exists()


def test_a_reference_without_steps_takes_an_empty_list(mobile_upload):  # noqa: F811
    client, _, payload = mobile_upload
    payload.update(step_summary_version="step-summary-v1", step_results=[])
    assert client.post(URL, payload, format="json").status_code == 201
    payload.update(
        id="7c9e6679-7425-40de-944b-e07fc1f90ae7",
        step_results=[
            {
                "index": 0,
                "start_ms": 0,
                "end_ms": 5000,
                "evaluated_ms": 0,
                "score": None,
            }
        ],
    )
    assert client.post(URL, payload, format="json").status_code == 400
