import subprocess
import sys
import types

import pytest

from ai_engine.playback import app_video
from ai_engine.playback.app_video import make_app_video, poster_time_ms
from ai_engine.pose.reference import ReferenceError


def test_the_poster_shows_the_dancer_alone_near_a_quarter_of_the_video():
    frames = [
        {"t": 0, "quality": "SINGLE_PERSON"},
        {"t": 1000, "quality": "MULTIPLE_PEOPLE"},
        {"t": 2000, "quality": "NO_USABLE_POSE"},
        {"t": 3000, "quality": "SINGLE_PERSON"},
    ]
    assert poster_time_ms(frames, 4000) == 0
    assert poster_time_ms(frames, 10000) == 3000


def test_without_a_clear_frame_the_poster_is_taken_at_a_quarter():
    assert poster_time_ms([{"t": 500, "quality": "MULTIPLE_PEOPLE"}], 8000) == 2000
    assert poster_time_ms(None, 8000) == 2000
    assert poster_time_ms([{"t": float("nan"), "quality": "SINGLE_PERSON"}], 0) == 0


@pytest.fixture
def ffmpeg(monkeypatch):
    """A fake imageio-ffmpeg and subprocess that record the commands."""
    calls = []
    state = {"frames": 45}
    module = types.SimpleNamespace(
        get_ffmpeg_exe=lambda: "ffmpeg",
        count_frames_and_secs=lambda path: (state["frames"], state["frames"] / 30),
    )
    monkeypatch.setitem(sys.modules, "imageio_ffmpeg", module)

    def run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(app_video.subprocess, "run", run)
    return calls, state


def test_the_sound_is_cut_or_padded_to_the_exact_length_of_the_picture(ffmpeg, tmp_path):
    calls, _ = ffmpeg
    assert make_app_video(tmp_path / "in.mov", tmp_path / "out.mp4", workspace=tmp_path) == 45
    picture, sound = calls
    assert "-an" in picture
    assert picture[picture.index("-vf") + 1].startswith("fps=30:start_time=0,")
    audio_filter = sound[sound.index("-af") + 1]
    assert "apad=whole_dur=1.500000" in audio_filter
    assert "atrim=end=1.500000" in audio_filter
    assert sound[sound.index("-c:v") + 1] == "copy"
    for command in calls:
        # Phones store the recording place in the file: it never reaches students.
        assert command[command.index("-map_metadata") + 1] == "-1"
        assert command[command.index("-protocol_whitelist") + 1] == "file,pipe"
    assert sound[-1] == str(tmp_path / "out.mp4")


def test_a_file_without_picture_is_refused(ffmpeg, tmp_path):
    calls, state = ffmpeg
    state["frames"] = 0
    with pytest.raises(ReferenceError, match="no tiene imagen"):
        make_app_video(tmp_path / "in.mov", tmp_path / "out.mp4", workspace=tmp_path)
    assert len(calls) == 1


def test_ffmpeg_errors_stay_private(ffmpeg, tmp_path, monkeypatch):
    def broken(command, **kwargs):
        raise subprocess.CalledProcessError(1, command, stderr=b"/private/path: invalid data")

    monkeypatch.setattr(app_video.subprocess, "run", broken)
    with pytest.raises(ReferenceError) as error:
        make_app_video(tmp_path / "in.mov", tmp_path / "out.mp4", workspace=tmp_path)
    assert "private" not in str(error.value)
