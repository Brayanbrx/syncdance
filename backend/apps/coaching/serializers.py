from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.routines.models import Routine

from .models import Assignment, Course, SessionNote
from .selectors import NO_EVIDENCE, assignment_status, visible_course_routines


def display_name(user):
    return user.get_full_name() or user.username


class JoinCourseSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=32, help_text="Código que da el instructor.")


class StudentAssignmentSerializer(serializers.ModelSerializer):
    """An assignment with the requesting student's progress. Evidence comes
    from the practices already synced; missing evidence is null, not zero."""

    routine_name = serializers.CharField(source="routine.name", read_only=True)
    # False when the routine left the catalog or went back to draft.
    routine_available = serializers.SerializerMethodField()
    best_stars = serializers.SerializerMethodField()
    practices = serializers.SerializerMethodField()

    def get_routine_available(self, obj) -> bool:
        return obj.routine.is_active and obj.routine.is_published

    last_practice_at = serializers.SerializerMethodField()
    completed = serializers.SerializerMethodField()
    overdue = serializers.SerializerMethodField()

    class Meta:
        model = Assignment
        fields = (
            "id",
            "routine",
            "routine_name",
            "routine_available",
            "target_stars",
            "due_date",
            "instructions",
            "best_stars",
            "practices",
            "last_practice_at",
            "completed",
            "overdue",
        )

    def _status(self, obj):
        cache = self.context.setdefault("assignment_status", {})
        if obj.pk not in cache:
            evidence = self.context.get("evidence", {}).get(obj.routine_id, NO_EVIDENCE)
            cache[obj.pk] = assignment_status(obj, evidence, today=self.context.get("today"))
        return cache[obj.pk]

    @extend_schema_field(serializers.IntegerField(allow_null=True, min_value=0, max_value=5))
    def get_best_stars(self, obj):
        return self._status(obj).evidence.best_stars

    @extend_schema_field(serializers.IntegerField(min_value=0))
    def get_practices(self, obj):
        return self._status(obj).evidence.practices

    @extend_schema_field(serializers.DateTimeField(allow_null=True))
    def get_last_practice_at(self, obj):
        value = self._status(obj).evidence.last_practice_at
        return None if value is None else serializers.DateTimeField().to_representation(value)

    @extend_schema_field(serializers.BooleanField())
    def get_completed(self, obj):
        return self._status(obj).completed

    @extend_schema_field(serializers.BooleanField())
    def get_overdue(self, obj):
        return self._status(obj).overdue


class CourseRoutineSerializer(serializers.ModelSerializer):
    class Meta:
        model = Routine
        fields = ("id", "name", "difficulty", "style", "duration_ms")
        read_only_fields = fields


class StudentCourseSerializer(serializers.ModelSerializer):
    instructor = serializers.SerializerMethodField()
    joined_at = serializers.DateTimeField(read_only=True)
    assignments = StudentAssignmentSerializer(many=True, read_only=True)
    # What the instructor published here: the course's own routines.
    routines = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = ("id", "name", "instructor", "joined_at", "assignments", "routines")

    @extend_schema_field(CourseRoutineSerializer(many=True))
    def get_routines(self, obj):
        routines = getattr(obj, "visible_routines", None)
        if routines is None:  # a course not loaded by courses_for_student
            routines = visible_course_routines(obj)
        return CourseRoutineSerializer(routines, many=True).data

    @extend_schema_field(serializers.CharField())
    def get_instructor(self, obj):
        return display_name(obj.instructor)


class SessionNoteSerializer(serializers.ModelSerializer):
    author = serializers.SerializerMethodField()
    routine_name = serializers.CharField(source="session.routine.name", read_only=True)
    session_started_at = serializers.DateTimeField(source="session.started_at", read_only=True)

    class Meta:
        model = SessionNote
        fields = (
            "id",
            "session",
            "routine_name",
            "session_started_at",
            "author",
            "text",
            "created_at",
        )
        read_only_fields = fields

    @extend_schema_field(serializers.CharField())
    def get_author(self, obj):
        return display_name(obj.author)
