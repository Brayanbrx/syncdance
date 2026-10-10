import gzip
import json
import math
import subprocess
import wave

import pytest

from ai_engine.choreography import body, steps
from ai_engine.choreography.body import Arm, Camera, Pose, skeleton
from ai_engine.choreography.curriculum import (
    GENERATOR_VERSION,
    STANDARD_V1,
    spec_digest,
)
from ai_engine.choreography.reference import SAMPLE_RATE, build_reference, samples
from ai_engine.features.body import extract_features


def distance(a, b):
    return math.dist(a, b)


def spec(key):
    return next(s for s in STANDARD_V1 if s.key == key)


def test_bones_keep_their_length_in_every_generated_pose():
    for routine in STANDARD_V1:
        timeline = routine.timeline()
        for index in range(0, round(timeline.duration_s * 12), 5):
            joints = skeleton(timeline.pose_at(index / 12))
            for side in ("left", "right"):
                assert distance(joints[f"{side}Hip"], joints[f"{side}Knee"]) == pytest.approx(
                    body.THIGH, abs=1e-6
                )
                assert distance(joints[f"{side}Knee"], joints[f"{side}Ankle"]) == pytest.approx(
                    body.SHIN, abs=1e-6
                )
                assert distance(joints[f"{side}Shoulder"], joints[f"{side}Elbow"]) == pytest.approx(
                    body.UPPER_ARM, abs=1e-6
                )
                assert distance(joints[f"{side}Elbow"], joints[f"{side}Wrist"]) == pytest.approx(
                    body.FOREARM, abs=1e-6
                )


def test_feet_land_where_the_step_sheet_says():
    pose = Pose(pelvis=(0.0, 0.85, 0.0), left_foot=(0.30, body.ANKLE_HEIGHT, 0.0))
    joints = skeleton(pose)
    assert joints["leftAnkle"] == pytest.approx((0.30, body.ANKLE_HEIGHT, 0.0), abs=1e-6)
    # Knees bend toward the camera, like a person, not backwards.
    assert joints["leftKnee"][2] > 0


def test_planted_feet_never_float_in_any_routine():
    """Wide stances lower the hips instead of lifting the feet off the floor."""
    for routine in STANDARD_V1:
        timeline = routine.timeline()
        for index in range(round(timeline.duration_s * 30)):
            pose = timeline.pose_at(index / 30)
            joints = skeleton(pose)
            for foot, name in ((pose.left_foot, "leftAnkle"), (pose.right_foot, "rightAnkle")):
                if foot[1] < body.ANKLE_HEIGHT + 0.03:
                    assert joints[name] == pytest.approx(foot, abs=2e-3), (routine.key, index)


def test_screen_right_is_the_coach_anatomical_left():
    """Mirror mode: the learner's right follows screen right."""
    timeline = spec("n1-step-touch-palmada").timeline()
    first_count = 4 * timeline.seconds_per_beat  # after the 4-beat lead-in
    landmarks = {p["joint"]: p for p in Camera().landmarks(timeline.pose_at(first_count))}
    assert landmarks["leftAnkle"]["x"] > 0.5 > landmarks["rightAnkle"]["x"]
    assert landmarks["leftAnkle"]["x"] - 0.5 > 0.5 - landmarks["rightAnkle"]["x"]


def test_raised_arms_and_knee_lift_are_visible_in_2d():
    camera = Camera()
    up = {p["joint"]: p for p in camera.landmarks(Pose().with_arms(steps.V_UP))}
    assert up["leftWrist"]["y"] < up["nose"]["y"]
    lift = Pose(left_foot=(body.FOOT, body.ANKLE_HEIGHT + 0.36, 0.30))
    knee = {p["joint"]: p for p in camera.landmarks(lift)}
    standing = {p["joint"]: p for p in camera.landmarks(Pose())}
    assert knee["leftKnee"]["y"] < standing["leftKnee"]["y"] - 0.05


def test_every_danced_sample_has_six_angles_and_the_lead_in_has_none():
    for routine in STANDARD_V1:
        timeline = routine.timeline()
        rows = list(samples(timeline))
        assert len(rows) == round(timeline.duration_s * SAMPLE_RATE)
        lead_in = round(4 * timeline.seconds_per_beat * SAMPLE_RATE)
        for index, (landmarks, aspect, people) in enumerate(rows):
            if index < lead_in - 1:
                assert people == 0 and landmarks == []
            elif index > lead_in:
                assert people == 1
                normalized, angles = extract_features(landmarks, aspect)
                assert len(angles) == 6, (routine.key, index)
                assert all(0 <= value <= 180 for value in angles.values())


def test_reference_is_exact_deterministic_and_marks_the_lead_in():
    routine = spec("n1-primer-baile")
    payload, artifact = build_reference(routine, source_sha256="b" * 64)
    again, _ = build_reference(routine, source_sha256="b" * 64)
    assert payload == again
    assert json.loads(gzip.decompress(payload)) == artifact
    assert artifact["engine"] == GENERATOR_VERSION
    assert artifact["model_sha256"] == spec_digest(routine)
    assert artifact["algorithm_version"] == "reference-body-v1"
    beats = 4 + 80
    assert artifact["duration_ms"] == pytest.approx(beats * 60_000 / 104, abs=84)
    qualities = [frame["quality"] for frame in artifact["frames"]]
    assert qualities[0] == "NO_USABLE_POSE"
    assert qualities[-1] == "SINGLE_PERSON"
    assert artifact["valid_frame_ratio"] > 0.9


def test_digest_changes_with_geometry_or_tempo():
    routine = spec("n1-marcha")
    faster = type(routine)(**{**routine.__dict__, "bpm": 120})
    assert spec_digest(routine) != spec_digest(faster)
    assert spec_digest(routine) == spec_digest(spec("n1-marcha"))


def test_cues_count_the_lead_in_and_announce_the_next_step():
    timeline = spec("n1-primer-baile").timeline()
    beat = timeline.seconds_per_beat
    assert timeline.cue_at(0.01).count == 5
    assert timeline.cue_at(3 * beat + 0.01).next_caption == "MARCHA CON BRAZOS"
    first = timeline.cue_at(4 * beat + 0.01)
    assert (first.caption, first.count, first.evaluated) == ("MARCHA CON BRAZOS", 1, True)
    assert timeline.cue_at(11 * beat + 0.01).next_caption == "STEP TOUCH + PALMADA"


def test_curriculum_shape():
    keys = [routine.key for routine in STANDARD_V1]
    assert len(keys) == len(set(keys)) == 6
    assert all(routine.difficulty == "BEGINNER" for routine in STANDARD_V1)
    assert all(routine.timeline().duration_s < 300 for routine in STANDARD_V1)


def test_arm_presets_are_symmetric():
    left = {p["joint"]: p for p in Camera().landmarks(Pose().with_arms(Arm(90, 0, 0)))}
    assert left["leftWrist"]["x"] - 0.5 == pytest.approx(0.5 - left["rightWrist"]["x"])


def test_audio_and_video_render_with_matching_length(tmp_path):
    pytest.importorskip("numpy")
    pytest.importorskip("cv2")
    imageio_ffmpeg = pytest.importorskip("imageio_ffmpeg")
    from ai_engine.choreography.media import render_video, synth_audio
    from ai_engine.choreography.timeline import Timeline

    timeline = Timeline([steps.intro(), steps.marcha()], 104)
    audio = tmp_path / "beat.wav"
    synth_audio(timeline, audio)
    with wave.open(str(audio)) as wav:
        assert wav.getnframes() / wav.getframerate() == pytest.approx(timeline.duration_s, abs=0.01)
    video = tmp_path / "coach.mp4"
    render_video(timeline, video, audio_path=audio, camera=Camera(320, 320, 127))
    probe = subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-i", str(video)],
        capture_output=True,
        text=True,
    ).stderr
    assert "Video: h264" in probe and "Audio: aac" in probe
    assert "yuv420p" in probe
