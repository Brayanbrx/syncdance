from django.contrib import admin

from .models import AppRelease


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    """Uploads go through the web panel, which checks and fingerprints the APK."""

    list_display = ("version_name", "version_code", "is_published", "published_at", "size_bytes")
    list_filter = ("is_published",)
    readonly_fields = tuple(field.name for field in AppRelease._meta.fields)

    def has_add_permission(self, request):
        return False
