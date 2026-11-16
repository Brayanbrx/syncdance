from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models
from django.utils import timezone


class Routine(models.Model):
    class Difficulty(models.TextChoices):
        BEGINNER = "BEGINNER", "Principiante"
        INTERMEDIATE = "INTERMEDIATE", "Intermedio"
        ADVANCED = "ADVANCED", "Avanzado"

    class Visibility(models.TextChoices):
        CATALOG = "CATALOG", "Catálogo SyncDance"
        COURSES = "COURSES", "Solo en cursos"

    class MusicRights(models.TextChoices):
        OWN = "OWN", "Música propia"
        LICENSED = "LICENSED", "Con licencia o permiso"
        FREE = "FREE", "Libre de derechos"

    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    instructor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="routines",
    )
    difficulty = models.CharField(max_length=16, choices=Difficulty.choices)
    style = models.CharField(max_length=40, blank=True)
    master_video = models.FileField(upload_to="routines/%Y/%m/", blank=True)
    # Provenance of third-party masters (default catalog). Media is downloaded at
    # install time from its source and never committed to the repository.
    catalog_key = models.SlugField(max_length=60, unique=True, null=True, blank=True)
    source_url = models.URLField(blank=True)
    license_name = models.CharField(max_length=120, blank=True)
    credit = models.CharField(max_length=200, blank=True)
    # Set for masters rendered from a choreography: their reference is exact and
    # comes from the step sheet, never from running pose detection on the video.
    generator = models.CharField(max_length=40, blank=True)
    # Step of the teaching path (generated standard, beginner first); null for
    # free-practice masters. The phone recommends the next step in this order.
    curriculum_position = models.PositiveSmallIntegerField(null=True, blank=True)
    duration_ms = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    # Who may see the routine once published. The SyncDance catalog is set by
    # platform administrators (that is the review); an instructor publishes
    # in their own courses (coaching.Course.published_routines).
    visibility = models.CharField(
        "visibilidad", max_length=12, choices=Visibility.choices, default=Visibility.CATALOG
    )
    # Null: a draft only its instructor sees. Administrators' routines and the
    # generated catalog are published on creation; the studio starts drafts.
    published_at = models.DateTimeField("publicada el", null=True, blank=True, default=timezone.now)
    # The instructor states the right to use the music before publishing.
    music_rights = models.CharField(
        "derechos de la música", max_length=12, choices=MusicRights.choices, blank=True
    )
    rights_declared_at = models.DateTimeField("derechos declarados el", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return self.name

    @property
    def is_published(self):
        return self.published_at is not None


class RoutineReference(models.Model):
    """Versioned offline artifact; never one database row per pose frame."""

    class Status(models.TextChoices):
        PENDING = "PENDING", "Pendiente"
        PROCESSING = "PROCESSING", "Procesando"
        READY = "READY", "Lista"
        FAILED = "FAILED", "Fallida"

    routine = models.ForeignKey(Routine, on_delete=models.PROTECT, related_name="references")
    version = models.PositiveIntegerField(validators=[MinValueValidator(1)])
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    engine_name = models.CharField(max_length=80, blank=True)
    pose_schema_version = models.CharField(max_length=40, default="pose-v1")
    feature_schema = models.CharField(max_length=40, default="motion-features-v1")
    algorithm_version = models.CharField(max_length=80, blank=True)
    sample_rate_hz = models.PositiveSmallIntegerField(default=12, validators=[MinValueValidator(1)])
    duration_ms = models.PositiveIntegerField(default=0)
    reference_asset = models.FileField(upload_to="references/%Y/%m/", blank=True)
    checksum_sha256 = models.CharField(
        max_length=64,
        blank=True,
        validators=[
            RegexValidator(r"\A[0-9a-f]{64}\Z", "Usar un SHA-256 hexadecimal en minúsculas.")
        ],
    )
    scoring_profile = models.JSONField(default=dict, blank=True)
    processing_error = models.TextField(blank=True)
    source_video = models.FileField(upload_to="routines/", blank=True)
    # What the phone downloads and plays: the light version made from the
    # upload (`ai_engine.playback.app_video`). The reference is computed from this
    # file, so `source_sha256` is its hash. Empty for versions made before it
    # existed and for generated masters, which serve `source_video` instead.
    playback_video = models.FileField(upload_to="routines/app/%Y/%m/", blank=True)
    playback_profile = models.CharField(max_length=40, blank=True)
    poster = models.FileField(upload_to="routines/posters/%Y/%m/", blank=True)
    source_sha256 = models.CharField(max_length=64, blank=True)
    processing_started_at = models.DateTimeField(null=True, blank=True)
    # Observability: the Celery task that owns this version and when it ended
    # (READY or FAILED), to find its log lines and spot slow or lost work.
    processing_task_id = models.CharField(max_length=64, blank=True)
    processing_finished_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-version",)
        constraints = [
            models.UniqueConstraint(fields=("routine", "version"), name="unique_routine_reference"),
        ]

    def __str__(self):
        return f"{self.routine} · ref-{self.version} ({self.status})"

    @property
    def video(self):
        """The file students play: the light version when there is one."""
        return self.playback_video or self.source_video

    def clean(self):
        super().clean()
        if self.status == self.Status.READY and (
            not self.reference_asset
            or not self.engine_name
            or not self.algorithm_version
            or not self.duration_ms
            or not self.checksum_sha256
        ):
            raise ValidationError(
                "Una referencia lista requiere archivo, checksum, motor, algoritmo y duración."
            )
