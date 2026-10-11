from rest_framework import serializers
from rest_framework.reverse import reverse

from .models import Routine, RoutineReference


class RoutineSerializer(serializers.ModelSerializer):
    instructor = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = Routine
        fields = (
            "id",
            "name",
            "description",
            "instructor",
            "difficulty",
            "style",
            "master_video",
            "duration_ms",
            "is_active",
            "catalog_key",
            "source_url",
            "license_name",
            "credit",
            "generator",
            "curriculum_position",
            "created_at",
            "updated_at",
        )
        read_only_fields = (
            "id",
            "instructor",
            "catalog_key",
            "generator",
            "curriculum_position",
            "created_at",
            "updated_at",
        )


class RoutineReferenceSerializer(serializers.ModelSerializer):
    download_url = serializers.SerializerMethodField()

    def get_download_url(self, obj) -> str | None:
        if obj.status != RoutineReference.Status.READY or not obj.reference_asset:
            return None
        return reverse(
            "routine-reference-download",
            kwargs={
                "pk": obj.routine_id,
                "version": obj.version,
            },
            request=self.context.get("request"),
        )

    class Meta:
        model = RoutineReference
        fields = (
            "id",
            "routine",
            "version",
            "status",
            "engine_name",
            "pose_schema_version",
            "feature_schema",
            "sample_rate_hz",
            "duration_ms",
            "algorithm_version",
            "reference_asset",
            "download_url",
            "processing_error",
            "source_sha256",
            "checksum_sha256",
            "scoring_profile",
            "created_at",
        )
        read_only_fields = fields
