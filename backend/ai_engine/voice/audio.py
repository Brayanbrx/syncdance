"""Any audio or video file to the samples the pitch tracker reads.

FFmpeg decodes the first audio stream to 16 kHz mono float samples. There is no
loudness normalization: it would flatten the dynamics the volume score
measures. Pitch tracking does not depend on the level.
"""

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
