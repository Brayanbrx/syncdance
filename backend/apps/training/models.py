import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

score_validators = [MinValueValidator(0), MaxValueValidator(100)]
ratio_validators = [MinValueValidator(0), MaxValueValidator(1)]


class DanceSession(models.Model):
    class Status(models.TextChoices):
        STARTED = "STARTED", "Iniciada"
        COMPLETED = "COMPLETED", "Completada"
        ABORTED = "ABORTED", "Abortada"
        FAILED = "FAILED", "Fallida"

    class Mode(models.TextChoices):
        LIVE = "LIVE", "En vivo"
        RECORDED = "RECORDED", "Grabada"

    # Client-generated UUID supports future offline synchronization.
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="dance_sessions"
    )
    routine = models.ForeignKey(
        "routines.Routine", on_delete=models.PROTECT, related_name="dance_sessions"
    )
    reference = models.ForeignKey(
        "routines.RoutineReference", on_delete=models.PROTECT, related_name="dance_sessions"
    )
    started_at = models.DateTimeField()
    finished_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.STARTED)
    mode = models.CharField(max_length=16, choices=Mode.choices, default=Mode.LIVE)
    overall_score = models.FloatField(null=True, blank=True, validators=score_validators)
    pose_score = models.FloatField(null=True, blank=True, validators=score_validators)
    timing_score = models.FloatField(null=True, blank=True, validators=score_validators)
    # Evaluated video time / duration; estimated sampled coverage, not observation.
    quality_ratio = models.FloatField(null=True, blank=True, validators=ratio_validators)
    # Null on sessions stored before the mobile summary contract existed.
    duration_ms = models.PositiveIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(300000)]
    )
    evaluated_ms = models.PositiveIntegerField(null=True, blank=True)
    angle_score = models.FloatField(null=True, blank=True, validators=score_validators)
    position_score = models.FloatField(null=True, blank=True, validators=score_validators)
    mean_error_degrees = models.FloatField(
        null=True, blank=True, validators=[MinValueValidator(0), MaxValueValidator(180)]
    )
    # Mean 2D distance in torso lengths; unbounded above.
    mean_position_error = models.FloatField(
        null=True, blank=True, validators=[MinValueValidator(0)]
    )
    reached_video_end = models.BooleanField(default=False)
    pose_schema_version = models.CharField(max_length=40)
    feature_schema_version = models.CharField(max_length=40)
    scoring_version = models.CharField(max_length=80)
    summary_version = models.CharField(max_length=80, blank=True)
    feedback_version = models.CharField(max_length=80, blank=True)
    reference_version = models.PositiveIntegerField(validators=[MinValueValidator(1)])
    synced_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-started_at",)

    def __str__(self):
        return f"{self.student} · {self.routine} ({self.status})"

    def clean(self):
        super().clean()
        if self.reference_id and self.reference.routine_id != self.routine_id:
            raise ValidationError({"reference": "La referencia no pertenece a esta rutina."})
        if self.finished_at and self.finished_at < self.started_at:
            raise ValidationError({"finished_at": "El fin no puede ser anterior al inicio."})
        if self.status != self.Status.STARTED and not self.finished_at:
            raise ValidationError({"finished_at": "Una sesión finalizada requiere fecha de fin."})
        if self.status == self.Status.STARTED and self.finished_at:
            raise ValidationError(
                {"finished_at": "Una sesión iniciada no puede tener fecha de fin."}
            )


class TimelineSegment(models.Model):
    """Contiguous video interval of the mobile summary; null score means no evidence."""

    session = models.ForeignKey(
        DanceSession, on_delete=models.CASCADE, related_name="timeline_segments"
    )
    start_ms = models.PositiveIntegerField()
    end_ms = models.PositiveIntegerField()
    evaluated_ms = models.PositiveIntegerField()
    score = models.FloatField(null=True, blank=True, validators=score_validators)

    class Meta:
        ordering = ("start_ms",)
        constraints = [
            models.UniqueConstraint(
                fields=("session", "start_ms"), name="unique_session_timeline_start"
            ),
            models.CheckConstraint(
                condition=models.Q(end_ms__gt=models.F("start_ms")),
                name="timeline_segment_time_order",
            ),
            models.CheckConstraint(
                condition=models.Q(evaluated_ms__lte=models.F("end_ms") - models.F("start_ms")),
                name="timeline_segment_evidence_within_interval",
            ),
            models.CheckConstraint(
                condition=models.Q(evaluated_ms=0, score__isnull=True)
                | models.Q(evaluated_ms__gt=0, score__isnull=False),
                name="timeline_segment_score_requires_evidence",
            ),
        ]

    def __str__(self):
        return f"{self.session_id} · {self.start_ms}-{self.end_ms}ms"


class FeedbackCount(models.Model):
    """Persistent cues actually shown on the phone, not every deviation."""

    session = models.ForeignKey(
        DanceSession, on_delete=models.CASCADE, related_name="feedback_counts"
    )
    code = models.CharField(max_length=100)
    region = models.CharField(max_length=100)
    message = models.CharField(max_length=500)
    count = models.PositiveIntegerField(validators=[MinValueValidator(1), MaxValueValidator(3000)])
    max_severity = models.FloatField(validators=[MinValueValidator(1)])

    class Meta:
        ordering = ("-count", "code")
        constraints = [
            models.UniqueConstraint(fields=("session", "code"), name="unique_session_feedback"),
        ]

    def __str__(self):
        return f"{self.code} ×{self.count}"


class SegmentScore(models.Model):
    class Segment(models.TextChoices):
        ARMS = "ARMS", "Brazos"
        TORSO = "TORSO", "Torso"
        HIPS = "HIPS", "Cadera"
        LEGS = "LEGS", "Piernas"

    session = models.ForeignKey(
        DanceSession, on_delete=models.CASCADE, related_name="segment_scores"
    )
    segment = models.CharField(max_length=16, choices=Segment.choices)
    # Missing evidence is null, not a zero score.
    score = models.FloatField(null=True, blank=True, validators=score_validators)
    coverage = models.FloatField(validators=ratio_validators)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=("session", "segment"), name="unique_session_segment"),
        ]

    def __str__(self):
        return f"{self.session_id} · {self.segment}"


class ErrorEvent(models.Model):
    class Severity(models.TextChoices):
        LOW = "LOW", "Baja"
        MEDIUM = "MEDIUM", "Media"
        HIGH = "HIGH", "Alta"

    session = models.ForeignKey(DanceSession, on_delete=models.CASCADE, related_name="error_events")
    code = models.CharField(max_length=80)
    body_part = models.CharField(max_length=16, choices=SegmentScore.Segment.choices)
    joint = models.CharField(max_length=40, blank=True)
    start_ms = models.PositiveIntegerField()
    end_ms = models.PositiveIntegerField()
    severity = models.CharField(max_length=16, choices=Severity.choices)
    magnitude = models.FloatField(validators=[MinValueValidator(0)])
    feedback_key = models.CharField(max_length=80)
    confidence = models.FloatField(validators=ratio_validators)

    class Meta:
        ordering = ("start_ms",)
        constraints = [
            models.CheckConstraint(
                condition=models.Q(end_ms__gte=models.F("start_ms")), name="error_event_time_order"
            ),
        ]

    def __str__(self):
        return f"{self.code} @ {self.start_ms}ms"
