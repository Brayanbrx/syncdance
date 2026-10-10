from django.contrib import admin

from .models import DanceSession, ErrorEvent, SegmentScore


class SegmentScoreInline(admin.TabularInline):
    model = SegmentScore
    extra = 0
    can_delete = False
    readonly_fields = ("segment", "score", "coverage")

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
    list_display = ("id", "student", "routine", "status", "overall_score", "started_at")
    list_filter = ("status", "mode")
    inlines = (SegmentScoreInline, ErrorEventInline)
    readonly_fields = tuple(field.name for field in DanceSession._meta.fields)

    def has_add_permission(self, request):
        return False
