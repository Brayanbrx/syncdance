"""The version of a master video that the phone downloads and plays.

The worker computes the reference from this file, never from the upload, so
the `video-start-cfr-v1` timeline matches what the student sees:

- the first frame sits at 0 ms and frames are evenly spaced (constant 30 fps)
- the phone's rotation is applied to the pixels
- the audio keeps its sync with the picture and ends where the video ends
- the short side is at most 720 px (H.264 and AAC in MP4, ready to stream)
- metadata such as the recording location is dropped

No Django imports. FFmpeg comes from imageio-ffmpeg, installed only on workers.
"""

import math
import subprocess
from pathlib import Path

from ai_engine.pose.reference import ReferenceError

# Any change to the commands below changes the file the reference is computed
# from: bump this version.
PROFILE = "app-video-v1"
FRAME_RATE = 30
SHORT_SIDE = 720
POSTER_LONG_SIDE = 640
MAX_SECONDS = 301

# FFmpeg applies display rotation before the filters. `start_time=0` pads with
# copies of the first frame when the audio starts first, so the picture and
# the sound keep their original sync.
VIDEO_FILTER = (
    f"fps={FRAME_RATE}:start_time=0,"
    "scale=trunc(iw*sar/2)*2:ih,setsar=1,"
    f"scale=w='if(gt(iw,ih),-2,min({SHORT_SIDE},iw))'"
    f":h='if(gt(iw,ih),trunc(min({SHORT_SIDE},ih)/2)*2,-2)'"
)
POSTER_FILTER = (
    f"scale=w='if(gt(iw,ih),min({POSTER_LONG_SIDE},iw),-2)'"
    f":h='if(gt(iw,ih),-2,min({POSTER_LONG_SIDE},ih))'"
)
# No shell, no remote protocols, no playlists.
SAFE_INPUT = ["-protocol_whitelist", "file,pipe", "-format_whitelist", "mov,matroska,avi"]
NO_METADATA = ["-map_metadata", "-1", "-map_chapters", "-1"]


def _ffmpeg():
    try:
        import imageio_ffmpeg
    except ImportError as exc:
        raise ReferenceError("Faltan las dependencias de procesamiento de video.") from exc
    return imageio_ffmpeg


def _run(command, *, message, timeout):
    try:
        subprocess.run(command, check=True, capture_output=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReferenceError(message) from exc


def make_app_video(source, target, *, workspace) -> int:
    """Write the app version of `source` to `target`; return its frame count."""
    ffmpeg = _ffmpeg()
    exe = ffmpeg.get_ffmpeg_exe()
    picture = Path(workspace) / "app-picture.mp4"
    failed = "No se pudo preparar el video para la app."
    # Pass 1: the picture alone, so its exact length is known before the audio.
    _run(
        [
            exe,
            *["-nostdin", "-v", "error", "-y", *SAFE_INPUT, "-i", str(source)],
            *["-map", "0:v:0", "-an", "-sn", "-dn", "-t", str(MAX_SECONDS)],
            *["-vf", VIDEO_FILTER],
            *["-c:v", "libx264", "-preset", "veryfast", "-crf", "23"],
            *["-maxrate", "2500k", "-bufsize", "5000k"],
            # A keyframe every second: seeking and step loops land precisely.
            *["-g", str(FRAME_RATE), "-profile:v", "high", "-pix_fmt", "yuv420p"],
            *NO_METADATA,
            str(picture),
        ],
        message=failed,
        timeout=900,
    )
    try:
        frames, _ = ffmpeg.count_frames_and_secs(str(picture))
    except (OSError, RuntimeError) as exc:
        raise ReferenceError(failed) from exc
    if frames <= 0:
        raise ReferenceError("El video no tiene imagen.")
    seconds = f"{frames / FRAME_RATE:.6f}"
    # Pass 2: the audio, trimmed or padded with silence to the picture's length.
    _run(
        [
            exe,
            *["-nostdin", "-v", "error", "-y", *SAFE_INPUT],
            *["-i", str(picture), "-i", str(source)],
            *["-map", "0:v:0", "-map", "1:a:0?", "-c:v", "copy"],
            *["-af", f"aresample=async=1:first_pts=0,apad=whole_dur={seconds},atrim=end={seconds}"],
            *["-c:a", "aac", "-b:a", "128k", "-ac", "2"],
            *NO_METADATA,
            *["-movflags", "+faststart"],
            str(target),
        ],
        message=failed,
        timeout=300,
    )
    return frames


def make_poster(video, target, *, at_ms) -> None:
    """A JPEG of one frame of the app version, for lists and previews."""
    exe = _ffmpeg().get_ffmpeg_exe()
    _run(
        [
            exe,
            *["-nostdin", "-v", "error", "-y", *SAFE_INPUT],
            *["-ss", f"{max(at_ms, 0) / 1000:.3f}", "-i", str(video)],
            *["-frames:v", "1", "-vf", POSTER_FILTER, "-q:v", "4", "-update", "1"],
            *NO_METADATA,
            str(target),
        ],
        message="No se pudo crear la miniatura.",
        timeout=60,
    )


def poster_time_ms(frames, duration_ms) -> int:
    """A moment where the dancer is alone and whole: the sample of a single
    person closest to a quarter of the video; a quarter of it otherwise."""
    target = round((duration_ms or 0) / 4)
    best = None
    for frame in frames or ():
        if frame.get("quality") != "SINGLE_PERSON":
            continue
        t = frame.get("t")
        if not isinstance(t, (int, float)) or not math.isfinite(t):
            continue
        if best is None or abs(t - target) < abs(best - target):
            best = t
    return int(best) if best is not None else target
