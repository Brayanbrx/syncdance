from django.contrib.auth import get_user_model
from django.urls import reverse
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.coaching.models import Course
from apps.routines.models import Routine

from .models import AppRelease

User = get_user_model()


class PublicReleaseSerializer(serializers.ModelSerializer):
    """What the landing page shows: never who uploaded it."""

    download_url = serializers.SerializerMethodField()

    class Meta:
        model = AppRelease
        fields = (
            "version_name",
            "version_code",
            "size_bytes",
            "sha256",
            "notes",
            "min_android",
            "published_at",
            "download_url",
        )

    @extend_schema_field(serializers.CharField())
    def get_download_url(self, obj):
        # Relative: the landing and the API share one origin behind nginx.
        return reverse("app-download")


class PanelReleaseSerializer(serializers.ModelSerializer):
    uploaded_by = serializers.SlugRelatedField(slug_field="username", read_only=True)
    apk = serializers.FileField(write_only=True)

    class Meta:
        model = AppRelease
        fields = (
            "id",
            "version_name",
            "version_code",
            "apk",
            "size_bytes",
            "sha256",
            "notes",
            "min_android",
            "is_published",
            "published_at",
            "uploaded_by",
            "created_at",
        )
        read_only_fields = ("size_bytes", "sha256", "published_at", "uploaded_by", "created_at")


class PanelReleaseUpdateSerializer(serializers.ModelSerializer):
    """After upload only the text and the publication change; a new build is a
    new version."""

    class Meta:
        model = AppRelease
        fields = ("version_name", "notes", "min_android", "is_published")


class PanelUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "email",
            "first_name",
            "last_name",
            "role",
            "is_active",
            "is_superuser",
            "last_login",
            "date_joined",
        )
        read_only_fields = ("id", "username", "is_superuser", "last_login", "date_joined")


class PanelUserCreateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ("id", "username", "email", "first_name", "last_name", "role", "password")
        read_only_fields = ("id",)


class PasswordSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True, min_length=8)


class PanelRoutineSerializer(serializers.ModelSerializer):
    instructor = serializers.SlugRelatedField(slug_field="username", read_only=True)
    sessions = serializers.IntegerField(source="session_total", read_only=True)
    reference_status = serializers.CharField(read_only=True, allow_null=True)
    reference_version = serializers.IntegerField(read_only=True, allow_null=True)

    class Meta:
        model = Routine
        fields = (
            "id",
            "name",
            "style",
            "difficulty",
            "curriculum_position",
            "generator",
            "instructor",
            "duration_ms",
            "is_active",
            "sessions",
            "reference_status",
            "reference_version",
        )
        read_only_fields = tuple(f for f in fields if f != "is_active")


class PanelCourseSerializer(serializers.ModelSerializer):
    instructor = serializers.SlugRelatedField(slug_field="username", read_only=True)
    students = serializers.IntegerField(source="student_total", read_only=True)
    assignments = serializers.IntegerField(source="assignment_total", read_only=True)

    class Meta:
        model = Course
        fields = (
            "id",
            "name",
            "instructor",
            "join_code",
            "accepts_students",
            "students",
            "assignments",
            "created_at",
        )
        read_only_fields = fields


class _UsersSummary(serializers.Serializer):
    students = serializers.IntegerField()
    instructors = serializers.IntegerField()
    admins = serializers.IntegerField()
    inactive = serializers.IntegerField()
    joined_last_7_days = serializers.IntegerField()


class _PracticeSummary(serializers.Serializer):
    sessions = serializers.IntegerField()
    games = serializers.IntegerField()
    sessions_last_7_days = serializers.IntegerField()
    active_students_last_7_days = serializers.IntegerField()


class _CatalogSummary(serializers.Serializer):
    routines = serializers.IntegerField()
    active_routines = serializers.IntegerField()
    references_ready = serializers.IntegerField()
    references_processing = serializers.IntegerField()
    references_failed = serializers.IntegerField()


class _CoursesSummary(serializers.Serializer):
    courses = serializers.IntegerField()
    enrollments = serializers.IntegerField()
    assignments = serializers.IntegerField()


class PlatformSummarySerializer(serializers.Serializer):
    users = _UsersSummary()
    practice = _PracticeSummary()
    catalog = _CatalogSummary()
    courses = _CoursesSummary()
    latest_release = PublicReleaseSerializer(allow_null=True)
