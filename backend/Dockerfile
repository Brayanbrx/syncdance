FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# MediaPipe Tasks loads GLES/EGL even when inference runs on CPU.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libgles2 libegl1 libglib2.0-0 libportaudio2 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-pose.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements-pose.txt

COPY . .

# Outside /app: the development bind mount must not hide the installed model.
ENV POSE_MODEL_PATH=/opt/syncdance/pose_landmarker_lite.task
RUN DJANGO_SETTINGS_MODULE=config.settings.test python manage.py install_pose_model

EXPOSE 8000

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
