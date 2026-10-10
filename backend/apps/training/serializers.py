import math

from rest_framework import serializers

from apps.routines.models import Routine, RoutineReference
from apps.routines.selectors import get_routines_for_user

from .models import DanceSession, ErrorEvent, FeedbackCount, SegmentScore, TimelineSegment

MAX_TIMELINE_SEGMENTS = 60
MAX_FEEDBACK_CODES = 64
# Metrics that exist only when some video time was evaluated (missing is not zero).
EVIDENCE_METRICS = (
    "pose_score",
    "angle_score",
    "position_score",
    "mean_error_degrees",
    "mean_position_error",
)


class FiniteFloatField(serializers.FloatField):
    def to_internal_value(self, data):
        value = super().to_internal_value(data)
        if not math.isfinite(value):
            raise serializers.ValidationError("El valor debe ser finito.")
        return value


class SegmentScoreSerializer(serializers.ModelSerializer):
    score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    coverage = FiniteFloatField(min_value=0, max_value=1)

    class Meta:
        model = SegmentScore
        fields = ("segment", "score", "coverage")


class TimelineSegmentSerializer(serializers.ModelSerializer):
    score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)

    class Meta:
        model = TimelineSegment
        fields = ("start_ms", "end_ms", "evaluated_ms", "score")

    def validate(self, attrs):
        if attrs["end_ms"] <= attrs["start_ms"]:
            raise serializers.ValidationError("El tramo termina antes de comenzar.")
        if attrs["evaluated_ms"] > attrs["end_ms"] - attrs["start_ms"]:
            raise serializers.ValidationError("La evidencia excede la duración del tramo.")
        if (attrs["evaluated_ms"] > 0) != (attrs.get("score") is not None):
            raise serializers.ValidationError("Solo un tramo con evidencia tiene score.")
        return attrs


class FeedbackCountSerializer(serializers.ModelSerializer):
    max_severity = FiniteFloatField(min_value=1)

    class Meta:
        model = FeedbackCount
        fields = ("code", "region", "message", "count", "max_severity")


class ErrorEventSerializer(serializers.ModelSerializer):
    magnitude = FiniteFloatField(min_value=0)
    confidence = FiniteFloatField(min_value=0, max_value=1)

    class Meta:
        model = ErrorEvent
        fields = (
            "code",
            "body_part",
            "joint",
            "start_ms",
            "end_ms",
            "severity",
            "magnitude",
            "feedback_key",
            "confidence",
        )

    def validate(self, attrs):
        if attrs["end_ms"] < attrs["start_ms"]:
            raise serializers.ValidationError("El evento termina antes de comenzar.")
        return attrs


class DanceSessionSerializer(serializers.ModelSerializer):
    """Client-calculated summary. The reference is given by PK or by routine + version."""

    id = serializers.UUIDField(required=False)
    routine = serializers.PrimaryKeyRelatedField(queryset=Routine.objects.none())
    reference = serializers.PrimaryKeyRelatedField(
        queryset=RoutineReference.objects.none(), required=False
    )
    reference_version = serializers.IntegerField(min_value=1, required=False)
    overall_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    pose_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    timing_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    angle_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    position_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    mean_error_degrees = FiniteFloatField(
        min_value=0, max_value=180, allow_null=True, required=False
    )
    mean_position_error = FiniteFloatField(min_value=0, allow_null=True, required=False)
    duration_ms = serializers.IntegerField(
        min_value=1, max_value=300000, allow_null=True, required=False
    )
    evaluated_ms = serializers.IntegerField(min_value=0, allow_null=True, required=False)
    segment_scores = SegmentScoreSerializer(many=True, required=False)
    timeline_segments = TimelineSegmentSerializer(many=True, required=False)
    feedback_counts = FeedbackCountSerializer(many=True, required=False)
    error_events = ErrorEventSerializer(many=True, required=False)

    class Meta:
        model = DanceSession
        fields = (
            "id",
            "student",
            "routine",
            "reference",
            "started_at",
            "finished_at",
            "status",
            "mode",
            "follow_mode",
            "playback_speed",
            "overall_score",
            "pose_score",
            "timing_score",
            "angle_score",
            "position_score",
            "mean_error_degrees",
            "mean_position_error",
            "quality_ratio",
            "duration_ms",
            "evaluated_ms",
            "reached_video_end",
            "pose_schema_version",
            "feature_schema_version",
            "scoring_version",
            "summary_version",
            "feedback_version",
            "reference_version",
            "synced_at",
            "segment_scores",
            "timeline_segments",
            "feedback_counts",
            "error_events",
        )
        read_only_fields = (
            "student",
            "quality_ratio",
            "pose_schema_version",
            "feature_schema_version",
            "synced_at",
        )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get("request")
        if request and request.user.is_authenticated:
            routines = get_routines_for_user(user=request.user)
            self.fields["routine"].queryset = routines
            self.fields["reference"].queryset = RoutineReference.objects.filter(
                routine__in=routines, status=RoutineReference.Status.READY
            ).exclude(reference_asset="")

    def validate(self, attrs):
        attrs["reference"] = self._resolve_reference(attrs)
        attrs.pop("reference_version", None)
        finished = attrs.get("finished_at")
        status = attrs.get("status", DanceSession.Status.STARTED)
        if finished and finished < attrs["started_at"]:
            raise serializers.ValidationError({"finished_at": "El fin es anterior al inicio."})
        if (status == DanceSession.Status.STARTED) == bool(finished):
            raise serializers.ValidationError(
                {"finished_at": "La fecha de fin no coincide con el estado."}
            )
        segments = attrs.get("segment_scores", [])
        if len({item["segment"] for item in segments}) != len(segments):
            raise serializers.ValidationError({"segment_scores": "Hay segmentos duplicados."})
        events = attrs.get("error_events", [])
        if len(events) > 500:
            raise serializers.ValidationError(
                {"error_events": "Enviar solo eventos relevantes (máximo 500)."}
            )
        if finished:
            duration_ms = (finished - attrs["started_at"]).total_seconds() * 1000
            if any(event["end_ms"] > duration_ms for event in events):
                raise serializers.ValidationError({"error_events": "Un evento excede la sesión."})
        self._validate_summary(attrs)
        return attrs

    def _resolve_reference(self, attrs):
        reference = attrs.get("reference")
        version = attrs.get("reference_version")
        if reference is None:
            if version is None:
                raise serializers.ValidationError(
                    {"reference": "Indica la referencia o su versión."}
                )
            reference = (
                self.fields["reference"]
                .queryset.filter(routine=attrs["routine"], version=version)
                .first()
            )
            if reference is None:
                raise serializers.ValidationError(
                    {"reference_version": "La versión de referencia no está disponible."}
                )
        if reference.routine_id != attrs["routine"].pk:
            raise serializers.ValidationError(
                {"reference": "La referencia pertenece a otra rutina."}
            )
        if version is not None and reference.version != version:
            raise serializers.ValidationError(
                {"reference_version": "No coincide con la referencia indicada."}
            )
        return reference

    def _validate_summary(self, attrs):
        """Mirror the invariants enforced by the mobile local-session-v1 parser."""
        duration = attrs.get("duration_ms")
        timeline = sorted(attrs.get("timeline_segments", []), key=lambda s: s["start_ms"])
        feedback = attrs.get("feedback_counts", [])
        if duration is None:
            if attrs.get("evaluated_ms") is not None or timeline or feedback:
                raise serializers.ValidationError(
                    {"duration_ms": "Un resumen con evidencia requiere su duración."}
                )
            return
        evaluated = attrs.get("evaluated_ms")
        if evaluated is None or evaluated > duration:
            raise serializers.ValidationError({"evaluated_ms": "Debe estar entre 0 y la duración."})
        if attrs["reference"].duration_ms and duration != attrs["reference"].duration_ms:
            raise serializers.ValidationError(
                {"duration_ms": "No coincide con la duración de la referencia."}
            )
        for name in ("summary_version", "feedback_version"):
            if not attrs.get(name):
                raise serializers.ValidationError({name: "Indica la versión del resumen."})
        for name in EVIDENCE_METRICS:
            if (attrs.get(name) is not None) != (evaluated > 0):
                raise serializers.ValidationError(
                    {name: "Solo existe cuando hay tiempo evaluado; nunca se rellena con cero."}
                )
        if not timeline or len(timeline) > MAX_TIMELINE_SEGMENTS:
            raise serializers.ValidationError(
                {"timeline_segments": "Se requieren entre 1 y 60 tramos."}
            )
        cursor = 0
        for segment in timeline:
            if segment["start_ms"] != cursor:
                raise serializers.ValidationError(
                    {"timeline_segments": "Los tramos deben ser contiguos desde 0."}
                )
            cursor = segment["end_ms"]
        if cursor != duration:
            raise serializers.ValidationError(
                {"timeline_segments": "Los tramos deben cubrir toda la duración."}
            )
        if sum(segment["evaluated_ms"] for segment in timeline) != evaluated:
            raise serializers.ValidationError(
                {"timeline_segments": "La evidencia de los tramos no suma el tiempo evaluado."}
            )
        if len(feedback) > MAX_FEEDBACK_CODES:
            raise serializers.ValidationError({"feedback_counts": "Máximo 64 códigos."})
        if len({item["code"] for item in feedback}) != len(feedback):
            raise serializers.ValidationError({"feedback_counts": "Hay códigos duplicados."})
        if feedback and evaluated == 0:
            raise serializers.ValidationError(
                {"feedback_counts": "No hay avisos sin tiempo evaluado."}
            )
