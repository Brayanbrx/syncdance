import logging
import tempfile
from pathlib import Path

from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from ai_engine.pose.reference import MAX_DURATION_SECONDS, MAX_SOURCE_BYTES
from apps.coaching.models import Course
from apps.notifications import events as notification_events
from apps.notifications.signals import safely
from apps.routines.models import Routine, RoutineReference
from apps.routines.services import create_routine, update_routine

from . import choreography
from .quality import quality_report

logger = logging.getLogger(__name__)

VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".webm", ".mkv"}
# Singing: the instructor's voice alone, recorded as audio or video.
VOICE_EXTENSIONS = VIDEO_EXTENSIONS | {".m4a", ".mp3", ".wav", ".aac", ".ogg", ".flac"}
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


def probe_voice(upload):
    """Seconds of audio in an upload; None when unreadable, False when the
    server has no FFmpeg (then the worker still checks while processing)."""
    try:
        from ai_engine.voice import VoiceError
        from ai_engine.voice.audio import duration_seconds
    except ImportError:
        return False
    with tempfile.TemporaryDirectory(prefix="syncdance-probe-") as workspace:
        if hasattr(upload, "temporary_file_path"):
            path = upload.temporary_file_path()
        else:
            path = Path(workspace) / ("upload" + Path(upload.name).suffix.lower())
            with open(path, "wb") as copy:
                for chunk in upload.chunks():
                    copy.write(chunk)
        try:
            return duration_seconds(path)
        except VoiceError:
            return False  # no FFmpeg binary here
        finally:
            upload.seek(0)


def check_master_video(upload, *, kind=Routine.Kind.DANCE) -> None:
    """Refuse at upload time what the worker would only reject minutes later."""
    if kind == Routine.Kind.SING:
        return check_voice(upload)
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


def check_voice(upload) -> None:
    """The instructor's voice for a singing routine: audio or video, 5 s to 5 min."""
    if Path(upload.name).suffix.lower() not in VOICE_EXTENSIONS:
        raise StudioError(
            "Sube tu voz como audio (M4A, MP3, WAV) o video (MP4, MOV).", field="master_video"
        )
    if upload.size > MAX_SOURCE_BYTES:
        raise StudioError("El archivo pesa más de 200 MB.", field="master_video")
    duration = probe_voice(upload)
    if duration is False:
        return
    if not duration:
        raise StudioError(
            "No se pudo leer el audio. Expórtalo como M4A o MP3 e inténtalo de nuevo.",
            field="master_video",
        )
    if duration > MAX_DURATION_SECONDS:
        raise StudioError("La grabación dura más de 5 minutos. Recórtala.", field="master_video")
    if duration < MIN_SECONDS:
        raise StudioError("La grabación debe durar al menos 5 segundos.", field="master_video")


def current_reference(routine):
    """Latest reference made from the routine's current master video."""
    references = [
        r for r in routine.references.all() if r.source_video.name == routine.master_video.name
    ]
    return max(references, key=lambda r: r.version, default=None)


def create_studio_routine(*, instructor, master_video, **fields) -> Routine:
    """Always a draft for the instructor's courses, even for administrators."""
    check_master_video(master_video, kind=fields.get("kind", Routine.Kind.DANCE))
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
    if fields.get("kind", routine.kind) != routine.kind:
        raise StudioError("Una rutina no cambia entre baile y canto: crea una nueva.", field="kind")
    video = fields.get("master_video")
    if video is not None:
        check_master_video(video, kind=routine.kind)
        fields["published_at"] = None
        routine.leave_catalog_review()
    return update_routine(routine=routine, **fields)


@transaction.atomic
def publish(*, routine, user, course_ids, music_rights=None, catalog=None) -> Routine:
    """Publish in the user's courses and, for a platform administrator, in the
    SyncDance catalog. `catalog` None leaves the catalog as it is; True or
    False puts the routine in or takes it out (administrators only: an
    instructor proposes it and an administrator reviews it)."""
    if catalog and not user.manages_all_courses:
        raise StudioError(
            "Solo un administrador publica en el catálogo: propónla desde el estudio.",
            field="catalog",
        )
    in_catalog = routine.visibility == Routine.Visibility.CATALOG
    if catalog is None or not user.manages_all_courses:
        catalog = in_catalog
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
    if not chosen and not catalog:
        if user.manages_all_courses:
            raise StudioError("Elige el catálogo o al menos un curso.", field="courses")
        raise StudioError("Elige al menos un curso.", field="courses")
    if chosen - set(own.values_list("pk", flat=True)):
        raise StudioError("Solo puedes publicar en tus cursos.", field="courses")
    freeze_choreography(routine=routine, reference=reference)
    if rights != routine.music_rights or routine.rights_declared_at is None:
        routine.music_rights = rights
        routine.rights_declared_at = timezone.now()
    routine.published_at = routine.published_at or timezone.now()
    fields = ["music_rights", "rights_declared_at", "published_at"]
    if catalog != in_catalog:
        fields += set_in_catalog(routine, user=user, wanted=catalog)
    routine.save(update_fields=fields)
    for course in own:
        if course.pk in chosen:
            course.published_routines.add(routine)
        else:
            course.published_routines.remove(routine)
    if catalog and not in_catalog:
        safely(notification_events.routine_entered_catalog, routine)
    logger.info(
        "routine published",
        extra={"routine_id": routine.pk, "courses": sorted(chosen), "catalog": catalog},
    )
    return routine


def set_in_catalog(routine, *, user, wanted) -> list[str]:
    """An administrator's own decision: it counts as an approved review (it
    also settles a proposal of theirs). Returns the changed fields."""
    if not wanted:
        routine.visibility = Routine.Visibility.COURSES
        routine.catalog_review = ""
        return ["visibility", "catalog_review"]
    routine.visibility = Routine.Visibility.CATALOG
    routine.catalog_review = Routine.CatalogReview.APPROVED
    routine.catalog_reviewed_at = timezone.now()
    routine.catalog_reviewed_by = user
    routine.catalog_review_note = ""
    return [
        "visibility",
        "catalog_review",
        "catalog_reviewed_at",
        "catalog_reviewed_by",
        "catalog_review_note",
    ]


def choreography_is_stale(routine) -> bool:
    """The tempo was marked on a video that has since been replaced."""
    draft = routine.choreography or {}
    return bool(draft) and draft.get("video") != routine.master_video.name


def save_choreography(*, routine, draft) -> Routine:
    """Keep the instructor's tempo and steps; students get them on publish."""
    if routine.is_singing:
        raise StudioError("Las rutinas de canto todavía no tienen compás ni pasos.", conflict=True)
    reference = current_reference(routine)
    if reference is None or reference.status != "READY":
        raise StudioError(
            "Espera a que termine el procesamiento del video para marcar el compás.",
            conflict=True,
        )
    try:
        cleaned = choreography.clean(draft, duration_ms=reference.duration_ms)
    except choreography.ChoreographyError as error:
        raise StudioError(str(error), field=error.field) from error
    routine.choreography = {**cleaned, "video": routine.master_video.name} if cleaned else {}
    routine.save(update_fields=["choreography"])
    return routine


def frozen_profile(routine, reference) -> dict:
    """The scoring_profile the draft would publish for this reference."""
    return choreography.profile(routine.choreography, duration_ms=reference.duration_ms)


def freeze_choreography(*, routine, reference) -> RoutineReference:
    """Publishing carries the tempo and steps to the phone. A READY version is
    never edited: when they changed, a new version reuses the same files (the
    analysis, the light video and the poster), with no reprocessing."""
    if routine.is_singing:
        return reference  # no tempo or steps yet for singing
    if choreography_is_stale(routine):
        raise StudioError(
            "Cambiaste el video: revisa el primer tiempo en «Compás y pasos» y guarda, o bórralos.",
            conflict=True,
        )
    wanted = frozen_profile(routine, reference)
    if wanted == reference.scoring_profile:
        return reference
    # Serialize version numbers for this routine, as queue_reference does.
    Routine.objects.select_for_update().get(pk=routine.pk)
    version = (routine.references.aggregate(value=Max("version"))["value"] or 0) + 1
    frozen = RoutineReference.objects.create(
        routine=routine,
        version=version,
        status=RoutineReference.Status.READY,
        engine_name=reference.engine_name,
        pose_schema_version=reference.pose_schema_version,
        feature_schema=reference.feature_schema,
        algorithm_version=reference.algorithm_version,
        sample_rate_hz=reference.sample_rate_hz,
        duration_ms=reference.duration_ms,
        reference_asset=reference.reference_asset.name,
        checksum_sha256=reference.checksum_sha256,
        source_video=reference.source_video.name,
        source_sha256=reference.source_sha256,
        playback_video=reference.playback_video.name,
        playback_profile=reference.playback_profile,
        poster=reference.poster.name,
        scoring_profile=wanted,
        processing_started_at=reference.processing_started_at,
        processing_finished_at=reference.processing_finished_at,
    )
    logger.info(
        "choreography frozen",
        extra={"routine_id": routine.pk, "version": version, "from_version": reference.version},
    )
    return frozen


def unpublish(*, routine) -> Routine:
    """Back to draft, out of the courses and out of the catalog."""
    routine.published_at = None
    routine.save(update_fields=["published_at", *routine.leave_catalog_review()])
    return routine


def propose_for_catalog(*, routine) -> Routine:
    """Ask a platform administrator to add the routine to the free catalog.
    Only a published routine: its rights, quality and courses are settled."""
    if not routine.is_published:
        raise StudioError(
            "Publícala primero en tus cursos: al catálogo llegan rutinas ya probadas.",
            conflict=True,
        )
    if routine.visibility == Routine.Visibility.CATALOG:
        raise StudioError("Ya está en el catálogo de SyncDance.", conflict=True)
    if routine.catalog_review == Routine.CatalogReview.PENDING:
        raise StudioError("Ya está en revisión.", conflict=True)
    routine.catalog_review = Routine.CatalogReview.PENDING
    routine.catalog_requested_at = timezone.now()
    routine.catalog_reviewed_at = None
    routine.catalog_reviewed_by = None
    routine.catalog_review_note = ""
    routine.save(
        update_fields=[
            "catalog_review",
            "catalog_requested_at",
            "catalog_reviewed_at",
            "catalog_reviewed_by",
            "catalog_review_note",
        ]
    )
    logger.info("routine proposed for the catalog", extra={"routine_id": routine.pk})
    return routine


def withdraw_from_catalog(*, routine) -> Routine:
    """Cancel a proposal, or take an approved routine out of the catalog; it
    stays published in the instructor's courses."""
    if routine.catalog_review not in (
        Routine.CatalogReview.PENDING,
        Routine.CatalogReview.APPROVED,
    ):
        raise StudioError("No está en el catálogo ni en revisión.", conflict=True)
    routine.save(update_fields=routine.leave_catalog_review())
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
