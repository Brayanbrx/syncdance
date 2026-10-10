"""Explicit provisioning; inference never downloads a model implicitly."""

import hashlib
import os
import urllib.request
from pathlib import Path
from tempfile import NamedTemporaryFile

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
)
MODEL_SHA256 = "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a"


class Command(BaseCommand):
    help = "Instala el modelo oficial MediaPipe Pose Landmarker Lite v1 si no existe."

    def handle(self, *args, **options):
        target = Path(settings.POSE_MODEL_PATH)
        if target.exists():
            self.stdout.write("El modelo ya existe; no se reemplazó.")
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        temp_path = None
        try:
            with (
                urllib.request.urlopen(MODEL_URL, timeout=60) as response,
                NamedTemporaryFile(dir=target.parent, delete=False) as output,
            ):
                temp_path = Path(output.name)
                size = 0
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > 50 * 1024 * 1024:
                        raise CommandError("El archivo del modelo excede el tamaño permitido.")
                    output.write(chunk)
            if size < 1024:
                raise CommandError("El modelo descargado está incompleto.")
            if hashlib.sha256(temp_path.read_bytes()).hexdigest() != MODEL_SHA256:
                raise CommandError("El checksum del modelo descargado no coincide.")
            os.replace(temp_path, target)
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            self.stdout.write(self.style.SUCCESS(f"Modelo instalado. SHA-256: {digest}"))
        except OSError as exc:
            raise CommandError("No se pudo instalar el modelo oficial.") from exc
        finally:
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)
