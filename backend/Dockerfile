FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# MediaPipe Tasks loads GLES/EGL even when inference runs on CPU.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libgles2 libegl1 libglib2.0-0 libportaudio2 fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-pose.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements-pose.txt

# Singing analysis, in its own layer so the pose dependencies stay cached.
COPY requirements-voice.txt ./
RUN pip install --no-cache-dir -r requirements-voice.txt

COPY . .

# Outside /app: the development bind mount must not hide the installed model.
ENV POSE_MODEL_PATH=/opt/syncdance/pose_landmarker_lite.task
RUN DJANGO_SETTINGS_MODULE=config.settings.test python manage.py install_pose_model

# Admin static files for WhiteNoise (production settings, hashed names). The
# key only satisfies the settings check: nothing is signed at build time.
RUN DJANGO_SETTINGS_MODULE=config.settings.production \
    DJANGO_SECRET_KEY=collectstatic-build-only \
    python manage.py collectstatic --noinput

EXPOSE 8000

# Production server. docker-compose.yml (development) runs runserver instead.
# Uploads arrive already buffered by nginx; the timeout covers large ones.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", \
     "--workers", "3", "--timeout", "300", "--forwarded-allow-ips", "*"]
