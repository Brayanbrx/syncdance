from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.coaching.models import Course
from apps.routines.models import Routine

from . import choreography
from .services import choreography_is_stale, current_reference, frozen_profile


class ProcessingSerializer(serializers.Serializer):
    """The reference of the current master video: whether students can dance it."""

    status = serializers.CharField()
    version = serializers.IntegerField()
    error = serializers.CharField(allow_blank=True)
    finished_at = serializers.DateTimeField(allow_null=True)
    light_video = serializers.BooleanField(help_text="Students download the 720p version.")
    poster = serializers.BooleanField()


class ChoreographyStepSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=choreography.NAME_LENGTH)
    start_beat = serializers.IntegerField(
        min_value=0, help_text="Beats from the first beat (0 = the first 1)."
    )
    counts = serializers.IntegerField(min_value=1, max_value=choreography.MAX_COUNTS)
    tip = serializers.CharField(
        max_length=choreography.TIP_LENGTH, allow_blank=True, required=False, default=""
    )


class ChoreographySerializer(serializers.Serializer):
    """Tempo and steps as the editor marks them; bpm null clears them."""

    bpm = serializers.FloatField(
        allow_null=True, min_value=choreography.MIN_BPM, max_value=choreography.MAX_BPM
    )
    first_beat_ms = serializers.IntegerField(allow_null=True, min_value=0)
    steps = ChoreographyStepSerializer(
        many=True, required=False, max_length=choreography.MAX_STEPS, default=list
    )


class ChoreographyStateSerializer(ChoreographySerializer):
    stale = serializers.BooleanField(help_text="Marked on a video since replaced.")
    unpublished_changes = serializers.BooleanField(
        help_text="Published, but students still have other tempo or steps."
    )


class StudioRoutineSerializer(serializers.ModelSerializer):
    processing = serializers.SerializerMethodField()
    choreography = serializers.SerializerMethodField()
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
            "catalog_review",
            "catalog_requested_at",
            "catalog_reviewed_at",
            "catalog_review_note",
            "duration_ms",
            "is_active",
            "processing",
            "choreography",
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

    @extend_schema_field(ChoreographyStateSerializer)
    def get_choreography(self, obj):
        draft = obj.choreography or {}
        stale = choreography_is_stale(obj)
        reference = current_reference(obj)
        changed = (
            obj.is_published
            and not stale
            and reference is not None
            and reference.status == "READY"
            and frozen_profile(obj, reference) != reference.scoring_profile
        )
        return {
            "bpm": draft.get("bpm"),
            "first_beat_ms": draft.get("first_beat_ms"),
            "steps": draft.get("steps", []),
            "stale": stale,
            "unpublished_changes": changed,
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
