"""Any audio or video file to the samples the pitch tracker reads.

FFmpeg decodes the first audio stream to 16 kHz mono float samples. There is no
loudness normalization: it would flatten the dynamics the volume score
measures. Pitch tracking does not depend on the level.
"""

import re
import subprocess
from pathlib import Path

import numpy as np

from ai_engine.voice import VoiceError

SAMPLE_RATE = 16000
MAX_SECONDS = 600
# No remote protocols and no playlists: a file that is really an HLS or concat
# list must not make the worker fetch anything.
SAFE_INPUT = [
    "-protocol_whitelist",
    "file,pipe",
    "-format_whitelist",
    "wav,mp3,mov,matroska,ogg,flac,aac",
]


# The file the phone plays. The reference is computed from it, never from the
# upload, so both share the same first sample. Any change here changes that
# file: bump the profile.
APP_AUDIO_PROFILE = "app-audio-v1"
APP_AUDIO = [
    "-vn",
    "-ac",
    "1",
    "-ar",
    "44100",
    "-c:a",
    "aac",
    "-b:a",
    "96k",
    "-map_metadata",
    "-1",
    "-map_chapters",
    "-1",
    # Same input, same bytes: no encoder name or dates inside the file.
    "-fflags",
    "+bitexact",
    "-flags:a",
    "+bitexact",
    "-movflags",
    "+faststart",
]


_DURATION = re.compile(rb"Duration: (\d+):(\d{2}):(\d{2}(?:\.\d+)?)")


def duration_seconds(path):
    """Length of a file's audio as FFmpeg reports it; None when unreadable."""
    command = [_ffmpeg_exe(), "-nostdin", "-hide_banner", *SAFE_INPUT, "-i", str(Path(path))]
    try:
        # Without an output FFmpeg exits with an error after printing the info.
        result = subprocess.run(command, capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    if b"Audio:" not in result.stderr:
        return None
    match = _DURATION.search(result.stderr)
    if not match:
        return None
    hours, minutes, seconds = match.groups()
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def make_app_audio(source, target, *, max_seconds=MAX_SECONDS):
    """AAC in MP4 (.m4a) from the first audio stream of any audio or video."""
    command = [
        _ffmpeg_exe(),
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        *SAFE_INPUT,
        "-i",
        str(Path(source)),
        "-map",
        "0:a:0",
        "-t",
        str(max_seconds + 1),
        *APP_AUDIO,
        "-f",
        "mp4",
        str(Path(target)),
    ]
    try:
        subprocess.run(command, check=True, capture_output=True, timeout=600)
    except (OSError, subprocess.SubprocessError) as exc:
        raise VoiceError("No se pudo leer el audio de la grabación.") from exc
    if not Path(target).exists() or Path(target).stat().st_size == 0:
        raise VoiceError("La grabación no tiene audio.")


def _ffmpeg_exe():
    try:
        import imageio_ffmpeg
    except ImportError as exc:
        raise VoiceError("Faltan las dependencias de procesamiento de audio.") from exc
    return imageio_ffmpeg.get_ffmpeg_exe()


def decode(path, *, max_seconds=MAX_SECONDS):
    """Samples of the first audio stream: float32, mono, `SAMPLE_RATE` Hz."""
    command = [
        _ffmpeg_exe(),
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        *SAFE_INPUT,
        "-i",
        str(Path(path)),
        "-map",
        "0:a:0",
        "-t",
        str(max_seconds + 1),
        "-ac",
        "1",
        "-ar",
        str(SAMPLE_RATE),
        "-f",
        "f32le",
        "pipe:1",
    ]
    try:
        result = subprocess.run(command, check=True, capture_output=True, timeout=300)
    except (OSError, subprocess.SubprocessError) as exc:
        raise VoiceError("No se pudo leer el audio de la grabación.") from exc
    samples = np.frombuffer(result.stdout, dtype="<f4").astype(np.float32)
    if samples.size == 0:
        raise VoiceError("La grabación no tiene audio.")
    if samples.size > max_seconds * SAMPLE_RATE:
        raise VoiceError(f"La grabación supera los {max_seconds // 60} minutos.")
    if not np.all(np.isfinite(samples)):
        raise VoiceError("No se pudo leer el audio de la grabación.")
    return samples
