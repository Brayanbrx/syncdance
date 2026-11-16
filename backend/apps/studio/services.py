import logging
import tempfile
from pathlib import Path

from django.db import transaction
from django.utils import timezone

from ai_engine.pose.reference import MAX_DURATION_SECONDS, MAX_SOURCE_BYTES
from apps.coaching.models import Course
from apps.routines.models import Routine
from apps.routines.services import create_routine, update_routine

from .quality import quality_report

logger = logging.getLogger(__name__)

VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".webm", ".mkv"}
MIN_SECONDS = 5
MIN_SHORT_SIDE = 360


class StudioError(Exception):
    """A request the studio refuses; the message is for the instructor."""

    def __init__(self, message, *, field=None, conflict=False):
        super().__init__(message)
        self.field = field
        self.conflict = conflict


def probe(upload) -> dict | None:
    """Duration and size of an uploaded video with FFmpeg; None when the
    server has no FFmpeg (then the worker still checks while processing)."""
    try:
        import imageio_ffmpeg
    except ImportError:
        logger.warning("video probe unavailable")
        return None
    with tempfile.TemporaryDirectory(prefix="syncdance-probe-") as workspace:
        # Large uploads already sit in a temporary file (Django's
        # TemporaryUploadedFile); small ones live in memory and are copied.
        if hasattr(upload, "temporary_file_path"):
            path = upload.temporary_file_path()
        else:
            path = Path(workspace) / "upload"
            with open(path, "wb") as copy:
                for chunk in upload.chunks():
                    copy.write(chunk)
        reader = imageio_ffmpeg.read_frames(str(path))
        try:
            meta = next(reader)
        except (RuntimeError, OSError, StopIteration):
            return {"duration": None, "size": None}
        finally:
            reader.close()
            upload.seek(0)
    return {"duration": meta.get("duration"), "size": meta.get("source_size") or meta.get("size")}


def check_master_video(upload) -> None:
    """Refuse at upload time what the worker would only reject minutes later."""
    if Path(upload.name).suffix.lower() not in VIDEO_EXTENSIONS:
        raise StudioError("Sube un video MP4, MOV, WEBM o MKV.", field="master_video")
    if upload.size > MAX_SOURCE_BYTES:
        raise StudioError(
            "El video pesa más de 200 MB. Expórtalo en 720p o 1080p.", field="master_video"
        )
    meta = probe(upload)
    if meta is None:
        return
    duration, size = meta.get("duration"), meta.get("size")
    if not duration:
        raise StudioError(
            "No se pudo leer el video. Exporta un MP4 (H.264) e inténtalo de nuevo.",
            field="master_video",
        )
    if duration > MAX_DURATION_SECONDS:
        raise StudioError("El video dura más de 5 minutos. Recórtalo.", field="master_video")
    if duration < MIN_SECONDS:
        raise StudioError("El video debe durar al menos 5 segundos.", field="master_video")
    if size and min(size) < MIN_SHORT_SIDE:
        raise StudioError(
            "La imagen es muy pequeña: usa al menos 360 píxeles de lado.", field="master_video"
        )


def current_reference(routine):
    """Latest reference made from the routine's current master video."""
    references = [
        r for r in routine.references.all() if r.source_video.name == routine.master_video.name
    ]
    return max(references, key=lambda r: r.version, default=None)


def create_studio_routine(*, instructor, master_video, **fields) -> Routine:
    """Always a draft for the instructor's courses, even for administrators."""
    check_master_video(master_video)
    return create_routine(
        instructor=instructor,
        master_video=master_video,
        visibility=Routine.Visibility.COURSES,
        published_at=None,
        **fields,
    )


@transaction.atomic
def update_studio_routine(*, routine, **fields) -> Routine:
    """A new video goes back to draft: its reference has to be processed and
    reviewed before students dance it."""
    video = fields.get("master_video")
    if video is not None:
        check_master_video(video)
        fields["published_at"] = None
    return update_routine(routine=routine, **fields)


@transaction.atomic
def publish(*, routine, user, course_ids, music_rights=None) -> Routine:
    rights = music_rights or routine.music_rights
    if not rights:
        raise StudioError("Indica de dónde es la música antes de publicar.", field="music_rights")
    reference = current_reference(routine)
    if reference is None or reference.status != "READY":
        raise StudioError(
            "La rutina todavía no está lista: espera a que termine el procesamiento.",
            conflict=True,
        )
    report = quality_report(reference)
    if report is not None and not report["publishable"]:
        raise StudioError(
            "En menos del 80 % del video se ve a una sola persona de cuerpo entero. "
            "Revisa el informe de calidad y graba de nuevo los tramos marcados.",
            conflict=True,
        )
    own = Course.objects.filter(instructor=user)
    chosen = set(course_ids)
    if not chosen:
        raise StudioError("Elige al menos un curso.", field="courses")
    if chosen - set(own.values_list("pk", flat=True)):
        raise StudioError("Solo puedes publicar en tus cursos.", field="courses")
    if rights != routine.music_rights or routine.rights_declared_at is None:
        routine.music_rights = rights
        routine.rights_declared_at = timezone.now()
    routine.published_at = routine.published_at or timezone.now()
    routine.save(update_fields=["music_rights", "rights_declared_at", "published_at"])
    for course in own:
        if course.pk in chosen:
            course.published_routines.add(routine)
        else:
            course.published_routines.remove(routine)
    logger.info("routine published", extra={"routine_id": routine.pk, "courses": sorted(chosen)})
    return routine


def unpublish(*, routine) -> Routine:
    routine.published_at = None
    routine.save(update_fields=["published_at"])
    return routine


@transaction.atomic
def delete_routine(*, routine) -> None:
    """Only a routine nobody practiced or was assigned: those records keep
    their students' history (retire it instead)."""
    if (
        routine.dance_sessions.exists()
        or routine.assignments.exists()
        or routine.performances.exists()
    ):
        raise StudioError(
            "Ya tiene prácticas o tareas: retírala de los cursos en lugar de borrarla.",
            conflict=True,
        )
    files = [routine.master_video] + [
        f
        for r in routine.references.all()
        for f in (r.reference_asset, r.source_video, r.playback_video, r.poster)
    ]
    routine.published_in_courses.clear()
    routine.references.all().delete()
    routine.delete()

    def remove_files():
        for stored in files:
            if stored and stored.name:
                stored.storage.delete(stored.name)

    transaction.on_commit(remove_files)
