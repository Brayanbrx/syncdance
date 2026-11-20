from django.contrib import admin

from .models import Notification, PushDevice


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "kind", "created_at", "read_at", "pushed_at")
    list_filter = ("kind",)
    search_fields = ("title", "user__username")
    readonly_fields = [field.name for field in Notification._meta.fields]

    def has_add_permission(self, request):
        return False


@admin.register(PushDevice)
class PushDeviceAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "app_version", "last_seen_at")
    search_fields = ("user__username",)
    readonly_fields = ("user", "token", "platform", "app_version", "created_at", "last_seen_at")

    def has_add_permission(self, request):
        return False
