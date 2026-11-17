from django.contrib import admin

from .models import AppErrorReport, AppRelease


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    """Uploads go through the web panel, which checks and fingerprints the APK."""

    list_display = ("version_name", "version_code", "is_published", "published_at", "size_bytes")
    list_filter = ("is_published",)
    readonly_fields = tuple(field.name for field in AppRelease._meta.fields)

    def has_add_permission(self, request):
        return False


@admin.register(AppErrorReport)
class AppErrorReportAdmin(admin.ModelAdmin):
    """Errors the Android app reported, grouped by version, kind and place."""

    list_display = ("kind", "app_version", "count", "last_seen", "message")
    list_filter = ("app_version",)
    search_fields = ("kind", "message", "stack")
    readonly_fields = tuple(field.name for field in AppErrorReport._meta.fields)

    def has_add_permission(self, request):
        return False
