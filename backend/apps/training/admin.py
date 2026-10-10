from django.contrib import admin

from .models import DanceSession, ErrorEvent, FeedbackCount, SegmentScore, TimelineSegment


class SegmentScoreInline(admin.TabularInline):
    model = SegmentScore
    extra = 0
    can_delete = False
    readonly_fields = ("segment", "score", "coverage")

    def has_add_permission(self, request, obj=None):
        return False


class TimelineSegmentInline(admin.TabularInline):
    model = TimelineSegment
    extra = 0
    can_delete = False
    readonly_fields = ("start_ms", "end_ms", "evaluated_ms", "score")

    def has_add_permission(self, request, obj=None):
        return False


class FeedbackCountInline(admin.TabularInline):
    model = FeedbackCount
    extra = 0
    can_delete = False
    readonly_fields = ("code", "region", "message", "count", "max_severity")

    def has_add_permission(self, request, obj=None):
        return False


class ErrorEventInline(admin.TabularInline):
    model = ErrorEvent
    extra = 0
    can_delete = False
    readonly_fields = (
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

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(DanceSession)
class DanceSessionAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "student",
        "routine",
        "status",
        "pose_score",
        "quality_ratio",
        "started_at",
    )
    list_filter = ("status", "mode", "follow_mode")
    inlines = (TimelineSegmentInline, FeedbackCountInline, SegmentScoreInline, ErrorEventInline)
    readonly_fields = tuple(field.name for field in DanceSession._meta.fields)

    def has_add_permission(self, request):
        return False
