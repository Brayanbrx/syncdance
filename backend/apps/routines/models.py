from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models


class Routine(models.Model):
    class Difficulty(models.TextChoices):
        BEGINNER = "BEGINNER", "Principiante"
        INTERMEDIATE = "INTERMEDIATE", "Intermedio"
        ADVANCED = "ADVANCED", "Avanzado"

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
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return self.name


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
