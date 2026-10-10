import math

from rest_framework import serializers

from apps.routines.models import Routine, RoutineReference
from apps.routines.selectors import get_routines_for_user

from .models import DanceSession, ErrorEvent, SegmentScore


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
    id = serializers.UUIDField(required=False)
    routine = serializers.PrimaryKeyRelatedField(queryset=Routine.objects.none())
    reference = serializers.PrimaryKeyRelatedField(queryset=RoutineReference.objects.none())
    overall_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    pose_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    timing_score = FiniteFloatField(min_value=0, max_value=100, allow_null=True, required=False)
    quality_ratio = FiniteFloatField(min_value=0, max_value=1, allow_null=True, required=False)
    segment_scores = SegmentScoreSerializer(many=True, required=False)
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
            "overall_score",
            "pose_score",
            "timing_score",
            "quality_ratio",
            "pose_schema_version",
            "feature_schema_version",
            "scoring_version",
            "reference_version",
            "synced_at",
            "segment_scores",
            "error_events",
        )
        read_only_fields = (
            "student",
            "pose_schema_version",
            "feature_schema_version",
            "reference_version",
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
        reference = attrs["reference"]
        if reference.routine_id != attrs["routine"].pk:
            raise serializers.ValidationError(
                {"reference": "La referencia pertenece a otra rutina."}
            )
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
        return attrs
