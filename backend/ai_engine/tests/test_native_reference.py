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


def ffmpeg(*args):
    import imageio_ffmpeg

    subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-nostdin", "-v", "error", "-y", *args],
        check=True,
        capture_output=True,
        timeout=60,
    )


def test_the_light_version_keeps_picture_and_sound_together(tmp_path):
    """A phone-like file: rotated, 59.94 fps, the picture starting 0.3 s after
    the sound, the sound 1 s longer. A flash and a beep share the 2.0 s mark."""
    import cv2
    import imageio_ffmpeg
    import numpy as np

    from ai_engine.playback.app_video import make_app_video, make_poster

    ffmpeg(
        *["-f", "lavfi", "-i", "color=black:s=1920x1080:r=60000/1001:d=6,"],
        *["-vf", "drawbox=w=iw:h=ih:color=white:t=fill:enable='between(t,1.7,1.8)'"],
        *["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"],
        str(tmp_path / "picture.mp4"),
    )
    ffmpeg(
        *["-f", "lavfi", "-i", "sine=f=1000:d=7.3"],
        *["-af", "volume=volume=0:enable='lt(t,2)+gt(t,2.1)'", "-c:a", "aac"],
        str(tmp_path / "sound.m4a"),
    )
    source = tmp_path / "phone.mov"
    ffmpeg(
        *["-display_rotation:v:0", "90", "-itsoffset", "0.3", "-i", str(tmp_path / "picture.mp4")],
        *["-i", str(tmp_path / "sound.m4a"), "-map", "0:v", "-map", "1:a", "-c", "copy"],
        *["-metadata", "location=+12.3456-076.5432/", str(source)],
    )
    light = tmp_path / "light.mp4"

    frames = make_app_video(source, light, workspace=tmp_path)

    assert frames == 189  # 6.3 s at 30 fps: the 0.3 s before the picture is kept
    capture = cv2.VideoCapture(str(light))
    assert capture.get(cv2.CAP_PROP_FPS) == 30
    assert (capture.get(cv2.CAP_PROP_FRAME_WIDTH), capture.get(cv2.CAP_PROP_FRAME_HEIGHT)) == (
        720,
        1280,
    )
    brightness = []
    while True:
        ok, image = capture.read()
        if not ok:
            break
        brightness.append(image.mean())
    capture.release()
    flash = next(i for i, value in enumerate(brightness) if value > 128) / 30
    sound = subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(light), "-map", "0:a:0"]
        + ["-ac", "1", "-ar", "48000", "-f", "s16le", "-"],
        capture_output=True,
        check=True,
    ).stdout
    pcm = np.frombuffer(sound, dtype=np.int16)
    beep = np.nonzero(np.abs(pcm) > 1000)[0][0] / 48000
    assert flash == pytest.approx(2.0, abs=0.001)
    assert beep == pytest.approx(2.0, abs=0.05)  # AAC adds its own ~20 ms ramp
    assert len(pcm) / 48000 == pytest.approx(6.3, abs=0.05)
    info = subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-i", str(light)],
        capture_output=True,
        text=True,
    ).stderr
    assert "location" not in info
    assert "rotation" not in info

    poster = tmp_path / "poster.jpg"
    make_poster(light, poster, at_ms=2000)
    image = cv2.imread(str(poster))
    assert image.shape[:2] == (640, 360)
    assert image.mean() > 128  # the flash frame
