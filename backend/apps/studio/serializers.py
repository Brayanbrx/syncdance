from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.coaching.models import Course
from apps.routines.models import Routine

from .services import current_reference


class ProcessingSerializer(serializers.Serializer):
    """The reference of the current master video: whether students can dance it."""

    status = serializers.CharField()
    version = serializers.IntegerField()
    error = serializers.CharField(allow_blank=True)
    finished_at = serializers.DateTimeField(allow_null=True)
    light_video = serializers.BooleanField(help_text="Students download the 720p version.")
    poster = serializers.BooleanField()


class StudioRoutineSerializer(serializers.ModelSerializer):
    processing = serializers.SerializerMethodField()
    courses = serializers.SerializerMethodField()
    is_published = serializers.BooleanField(read_only=True)

    class Meta:
        model = Routine
        fields = (
            "id",
            "name",
            "description",
            "difficulty",
            "style",
            "visibility",
            "is_published",
            "published_at",
            "music_rights",
            "rights_declared_at",
            "duration_ms",
            "is_active",
            "processing",
            "courses",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields

    @extend_schema_field(ProcessingSerializer(allow_null=True))
    def get_processing(self, obj):
        reference = current_reference(obj)
        if reference is None:
            return None
        return {
            "status": reference.status,
            "version": reference.version,
            "error": reference.processing_error if reference.status == "FAILED" else "",
            "finished_at": reference.processing_finished_at,
            "light_video": bool(reference.playback_video),
            "poster": bool(reference.poster),
        }

    @extend_schema_field(serializers.ListField(child=serializers.IntegerField()))
    def get_courses(self, obj):
        """The instructor's courses where the routine is published."""
        user = self.context["request"].user
        return sorted(c.pk for c in obj.published_in_courses.all() if c.instructor_id == user.pk)


class StudioRoutineWriteSerializer(serializers.ModelSerializer):
    master_video = serializers.FileField(required=False)

    class Meta:
        model = Routine
        fields = ("name", "description", "difficulty", "style", "music_rights", "master_video")


class PublishSerializer(serializers.Serializer):
    courses = serializers.ListField(child=serializers.IntegerField(), allow_empty=True)
    music_rights = serializers.ChoiceField(
        choices=Routine.MusicRights.choices, required=False, allow_blank=True
    )


class StudioCourseSerializer(serializers.ModelSerializer):
    students = serializers.IntegerField(read_only=True)

    class Meta:
        model = Course
        fields = ("id", "name", "join_code", "accepts_students", "students")
        read_only_fields = fields


class QualityProblemSerializer(serializers.Serializer):
    start_ms = serializers.IntegerField()
    end_ms = serializers.IntegerField()
    kind = serializers.CharField()


class QualityReportSerializer(serializers.Serializer):
    version = serializers.CharField()
    samples = serializers.IntegerField()
    duration_ms = serializers.IntegerField(allow_null=True)
    single_person = serializers.FloatField(allow_null=True)
    no_usable_pose = serializers.FloatField(allow_null=True)
    multiple_people = serializers.FloatField(allow_null=True)
    problems = QualityProblemSerializer(many=True)
    min_usable_ratio = serializers.FloatField()
    publishable = serializers.BooleanField()
