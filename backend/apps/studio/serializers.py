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


# --- course progress (E5) -----------------------------------------------------


class CourseRoutineOptionSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    name = serializers.CharField()
    steps = serializers.IntegerField(help_text="Steps students have in the published version.")


class StudioCourseDetailSerializer(StudioCourseSerializer):
    routines = serializers.SerializerMethodField()

    class Meta(StudioCourseSerializer.Meta):
        fields = (*StudioCourseSerializer.Meta.fields, "routines")
        read_only_fields = fields

    @extend_schema_field(CourseRoutineOptionSerializer(many=True))
    def get_routines(self, obj):
        from .progress import _steps_of, course_routines, published_reference

        return [
            {"id": r.pk, "name": r.name, "steps": len(_steps_of(published_reference(r)))}
            for r in course_routines(obj)
        ]


class MapQuerySerializer(serializers.Serializer):
    routine = serializers.IntegerField(min_value=1)
    follow_mode = serializers.ChoiceField(choices=("mirror", "same-side"), default="mirror")
    speed = serializers.ChoiceField(choices=("0.5", "0.75", "1", "1.0"), default="1")


class StepErrorSerializer(serializers.Serializer):
    code = serializers.CharField()
    message = serializers.CharField()
    region = serializers.CharField(allow_blank=True)
    students = serializers.IntegerField()
    count = serializers.IntegerField()


class StepSummarySerializer(serializers.Serializer):
    index = serializers.IntegerField()
    name = serializers.CharField()
    counts = serializers.IntegerField()
    start_ms = serializers.IntegerField()
    end_ms = serializers.IntegerField()
    students = serializers.IntegerField(help_text="Students with evidence on this step.")
    median = serializers.FloatField(allow_null=True)
    below_threshold = serializers.FloatField(allow_null=True)
    frequent_errors = StepErrorSerializer(many=True)


class MapStudentSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    name = serializers.CharField()
    practices = serializers.IntegerField()
    last_practice_at = serializers.DateTimeField(allow_null=True)
    scores = serializers.ListField(child=serializers.FloatField(allow_null=True))


class MapRoutineSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    name = serializers.CharField()


class DifficultyMapSerializer(serializers.Serializer):
    version = serializers.CharField()
    routine = MapRoutineSerializer()
    reference_version = serializers.IntegerField(allow_null=True)
    follow_mode = serializers.CharField()
    speed = serializers.FloatField()
    min_group = serializers.IntegerField()
    threshold = serializers.FloatField()
    steps = StepSummarySerializer(many=True)
    students = MapStudentSerializer(many=True)


class ConcordanceSerializer(serializers.Serializer):
    pairs = serializers.IntegerField()
    spearman = serializers.FloatField(allow_null=True)


class PracticeRowSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    student = serializers.SerializerMethodField()
    routine_name = serializers.CharField(source="routine.name")
    started_at = serializers.DateTimeField()
    follow_mode = serializers.CharField()
    playback_speed = serializers.FloatField()
    score = serializers.FloatField(source="pose_score", allow_null=True)
    coverage = serializers.FloatField(source="quality_ratio", allow_null=True)
    stars = serializers.SerializerMethodField()
    rating = serializers.SerializerMethodField()

    @extend_schema_field(serializers.CharField())
    def get_student(self, obj):
        from apps.coaching.serializers import display_name

        return display_name(obj.student)

    @extend_schema_field(serializers.IntegerField(allow_null=True))
    def get_stars(self, obj):
        game = getattr(obj, "game", None)
        return game.stars if game else None

    @extend_schema_field(serializers.IntegerField(allow_null=True))
    def get_rating(self, obj):
        mine = getattr(obj, "my_ratings", [])
        return mine[0].rating if mine else None


class CoursePracticesSerializer(serializers.Serializer):
    concordance = ConcordanceSerializer()
    practices = PracticeRowSerializer(many=True)


class RatingSerializer(serializers.Serializer):
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(
        max_length=1000,
        allow_blank=True,
        required=False,
        default="",
        help_text="Optional; saved as an observation the student reads.",
    )
