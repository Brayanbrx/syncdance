import gzip
import json
from pathlib import Path

import pytest

from ai_engine.features.body import extract_features
from ai_engine.pose.reference import ReferenceError, encode_reference


@pytest.fixture
def pose():
    # Same fixture as Dart: a change of geometry must pass on both runtimes.
    path = Path(__file__).resolve().parents[3] / "mobile/test/fixtures/poses/body_angles_v1.json"
    return json.loads(path.read_text())


def test_geometry_matches_mobile_fixture(pose):
    normalized, angles = extract_features(pose["landmarks"], pose["image_aspect_ratio"])
    assert normalized["leftShoulder"] == pytest.approx([-0.6, -1])
    assert len(angles) == 6
    for name, angle in angles.items():
        assert angle == pytest.approx(180 if name == "rightKnee" else 90)
    for point in pose["landmarks"]:
        point["x"] = point["x"] * 0.5 + 0.1
        point["y"] = point["y"] * 0.5 + 0.2
    moved, measured = extract_features(pose["landmarks"], 0.75)
    assert measured == pytest.approx(angles)
    for joint in normalized:
        assert moved[joint] == pytest.approx(normalized[joint])


def test_missing_joint_does_not_become_zero(pose):
    points = [p for p in pose["landmarks"] if p["joint"] != "leftWrist"]
    normalized, angles = extract_features(points, 0.75)
    assert "leftWrist" not in normalized
    assert "leftElbow" not in angles
    assert angles["rightElbow"] == pytest.approx(90)
    points = [p for p in points if p["joint"] != "leftHip"]
    assert extract_features(points, 0.75) == ({}, {})


def test_artifact_reproducible_preserves_timeline_and_missing_samples(pose):
    torso = [
        p
        for p in pose["landmarks"]
        if p["joint"] in ("leftHip", "rightHip", "leftShoulder", "rightShoulder")
    ]
    samples = [(pose["landmarks"], 0.75, 1), (torso, 0.75, 1), ([], 0.75, 2)]
    kwargs = dict(sample_rate=12, engine="fixture", model_sha256="a" * 64, source_sha256="b" * 64)
    payload, artifact = encode_reference(samples, **kwargs)
    assert payload == encode_reference(samples, **kwargs)[0]
    assert json.loads(gzip.decompress(payload)) == artifact
    fixture = (
        Path(__file__).resolve().parents[3]
        / "mobile/test/fixtures/references/reference_v1.json.gz"
    )
    assert payload == fixture.read_bytes()
    assert artifact == json.loads(fixture.with_suffix("").read_text())
    assert artifact["duration_ms"] == 250
    assert [f["t"] for f in artifact["frames"]] == [0, 83, 167]
    assert artifact["frames"][1]["angles"] == {}
    assert artifact["frames"][1]["normalized"]
    assert artifact["frames"][1]["quality"] == "NO_USABLE_POSE"
    assert artifact["frames"][2]["quality"] == "MULTIPLE_PEOPLE"
    assert artifact["valid_frame_ratio"] == pytest.approx(1 / 3)


def test_empty_unusable_and_oversize_timeline_fail(pose, monkeypatch):
    kwargs = dict(sample_rate=12, engine="fixture", model_sha256="a" * 64, source_sha256="b" * 64)
    for samples in [[], [([], 0.75, 0)], [(pose["landmarks"], 0.75, 2)]]:
        with pytest.raises(ReferenceError):
            encode_reference(samples, **kwargs)
    monkeypatch.setattr("ai_engine.pose.reference.MAX_DURATION_SECONDS", 1)
    with pytest.raises(ReferenceError, match="5 minutos"):
        encode_reference([(pose["landmarks"], 0.75, 1)] * 13, **kwargs)
