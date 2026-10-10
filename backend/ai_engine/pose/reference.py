"""Offline video-to-reference adapter. Native dependencies are loaded only by workers."""

import gzip
import hashlib
import json
import math
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from ai_engine.features.body import JOINTS, extract_features

MAX_SOURCE_BYTES = 200 * 1024 * 1024
MAX_DURATION_SECONDS = 300
ALGORITHM_VERSION = "reference-body-v1"


class ReferenceError(Exception):
    """Public processing error; must contain no filesystem paths or native logs."""


def encode_reference(samples, *, sample_rate, engine, model_sha256, source_sha256):
    frames = []
    valid = 0
    for index, (landmarks, aspect_ratio, person_count) in enumerate(samples):
        if index >= MAX_DURATION_SECONDS * sample_rate:
            raise ReferenceError("El video supera el límite de 5 minutos.")
        normalized, angles = (
            extract_features(landmarks, aspect_ratio) if person_count == 1 else ({}, {})
        )
        quality = "SINGLE_PERSON" if angles else "NO_USABLE_POSE"
        if person_count > 1:
            quality = "MULTIPLE_PEOPLE"
        valid += bool(angles)
        frames.append(
            {
                "t": round(index * 1000 / sample_rate),
                "angles": angles,
                "normalized": normalized,
                "quality": quality,
            }
        )
    if not frames or valid == 0:
        raise ReferenceError("El video no contiene poses utilizables de una sola persona.")
    artifact = {
        "schema": "motion-features-v1",
        "pose_schema": "pose-v1",
        "feature_schema": "body-features-v1",
        "normalization": "body-normalized-v1",
        "algorithm_version": ALGORITHM_VERSION,
        "engine": engine,
        "model_sha256": model_sha256,
        "source_sha256": source_sha256,
        "sample_rate_hz": sample_rate,
        "duration_ms": round(len(frames) * 1000 / sample_rate),
        "timeline": "video-start-cfr-v1",
        "smoothing": "none",
        "valid_frame_ratio": valid / len(frames),
        "frames": frames,
    }
    payload = gzip.compress(
        json.dumps(artifact, sort_keys=True, separators=(",", ":"), allow_nan=False).encode(),
        mtime=0,
    )
    return payload, artifact


def build_reference(source_path, *, model_path, sample_rate=12):
    if sample_rate != 12:
        raise ReferenceError("Esta versión de referencia requiere 12 muestras/s.")
    model_path = Path(model_path)
    if not model_path.is_file():
        raise ReferenceError("Falta instalar el modelo de pose del servidor.")
    try:
        import cv2
        import imageio_ffmpeg
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions
        from mediapipe.tasks.python.vision import (
            PoseLandmarker,
            PoseLandmarkerOptions,
            RunningMode,
        )
    except ImportError as exc:
        raise ReferenceError("Faltan las dependencias de procesamiento de video.") from exc

    model_hash = hashlib.sha256(model_path.read_bytes()).hexdigest()
    with open(source_path, "rb") as source:
        source_hash = hashlib.file_digest(source, "sha256").hexdigest()
    with TemporaryDirectory(prefix="syncdance-reference-") as workspace:
        video_path = Path(workspace) / "sampled.mp4"
        # FFmpeg applies display rotation and resamples VFR by presentation time.
        # No shell interpolation, remote protocols, audio or arbitrary playlists.
        command = [
            imageio_ffmpeg.get_ffmpeg_exe(),
            "-nostdin",
            "-v",
            "error",
            "-y",
            "-protocol_whitelist",
            "file,pipe",
            "-format_whitelist",
            "mov,matroska,avi",
            "-i",
            str(source_path),
            "-map",
            "0:v:0",
            "-an",
            "-t",
            "301",
            "-vf",
            "setpts=PTS-STARTPTS,fps=12,scale=trunc(iw*sar/2)*2:ih,setsar=1,"
            "scale=960:960:force_original_aspect_ratio=decrease:force_divisible_by=2",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            str(video_path),
        ]
        try:
            subprocess.run(command, check=True, capture_output=True, timeout=600)
        except (OSError, subprocess.SubprocessError) as exc:
            raise ReferenceError("No se pudo decodificar el video maestro.") from exc
        capture = cv2.VideoCapture(str(video_path))
        options = PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(model_path)),
            running_mode=RunningMode.VIDEO,
            num_poses=2,
        )
        try:
            if not capture.isOpened():
                raise ReferenceError("No se pudo abrir el video normalizado.")
            expected_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
            if expected_frames > MAX_DURATION_SECONDS * sample_rate:
                raise ReferenceError("El video supera el límite de 5 minutos.")
            with PoseLandmarker.create_from_options(options) as detector:

                def samples():
                    index = 0
                    while True:
                        ok, image = capture.read()
                        if not ok:
                            if index != expected_frames:
                                raise ReferenceError("El video se interrumpió durante la lectura.")
                            break
                        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                        result = detector.detect_for_video(
                            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                            round(index * 1000 / sample_rate),
                        )
                        landmarks = []
                        if len(result.pose_landmarks) == 1:
                            for name, p in zip(JOINTS, result.pose_landmarks[0], strict=True):
                                confidence = min(p.visibility or 0, p.presence or 0)
                                if all(math.isfinite(v) for v in (p.x, p.y, confidence)):
                                    landmarks.append(
                                        {
                                            "joint": name,
                                            "x": p.x,
                                            "y": p.y,
                                            "confidence": confidence,
                                        }
                                    )
                        yield landmarks, image.shape[1] / image.shape[0], len(result.pose_landmarks)
                        index += 1

                return encode_reference(
                    samples(),
                    sample_rate=sample_rate,
                    engine=f"mediapipe-{mp.__version__}",
                    model_sha256=model_hash,
                    source_sha256=source_hash,
                )
        finally:
            capture.release()
