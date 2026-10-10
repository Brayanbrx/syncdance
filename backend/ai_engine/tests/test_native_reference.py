"""Optional real engine smoke tests; no network and no user media in unit CI.

Set RUN_NATIVE_POSE_TESTS=1 after installing requirements-pose.txt and the model.
POSE_TEST_IMAGE may point to an official pose example to exercise successful detection.
"""

import gzip
import json
import os
import subprocess
from pathlib import Path

import pytest
from django.conf import settings

from ai_engine.pose.reference import ReferenceError, build_reference

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_NATIVE_POSE_TESTS") != "1", reason="Native engine smoke test is opt-in"
)


def make_video(path, *, image=None):
    import imageio_ffmpeg

    source = (
        ["-loop", "1", "-i", image]
        if image
        else ["-f", "lavfi", "-i", "color=black:s=640x480:r=24"]
    )
    subprocess.run(
        [
            imageio_ffmpeg.get_ffmpeg_exe(),
            "-nostdin",
            "-v",
            "error",
            "-y",
            *source,
            "-t",
            "1",
            "-r",
            "24",
            "-vf",
            "scale=640:480",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(path),
        ],
        check=True,
        capture_output=True,
        timeout=30,
    )


def test_real_decoder_and_model_reject_empty_scene(tmp_path):
    video = tmp_path / "empty.mp4"
    make_video(video)
    with pytest.raises(ReferenceError, match="poses utilizables"):
        build_reference(video, model_path=settings.POSE_MODEL_PATH)


def test_real_decoder_and_model_build_artifact(tmp_path):
    image = os.getenv("POSE_TEST_IMAGE")
    if not image or not Path(image).is_file():
        pytest.skip("Set POSE_TEST_IMAGE to a local pose sample")
    video = tmp_path / "pose.mp4"
    make_video(video, image=image)
    payload, artifact = build_reference(video, model_path=settings.POSE_MODEL_PATH)
    assert json.loads(gzip.decompress(payload)) == artifact
    assert artifact["duration_ms"] == 1000
    assert len(artifact["frames"]) == 12
    assert artifact["valid_frame_ratio"] > 0
    assert len(artifact["model_sha256"]) == 64
    assert artifact["engine"].startswith("mediapipe-")
    assert any(frame["angles"] for frame in artifact["frames"])
