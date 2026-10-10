from django.contrib import admin

from .models import Routine, RoutineReference
from .reference_services import queue_reference


@admin.register(Routine)
class RoutineAdmin(admin.ModelAdmin):
    list_display = ("name", "instructor", "difficulty", "duration_ms", "is_active")
    list_filter = ("difficulty", "is_active")
    search_fields = ("name",)
    actions = ("generate_references",)

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        if not change or "master_video" in form.changed_data:
            obj.duration_ms = 0
            obj.save(update_fields=["duration_ms"])
            if obj.master_video:
                queue_reference(routine_id=obj.pk)

    @admin.action(description="Generar nueva referencia del video maestro", permissions=["change"])
    def generate_references(self, request, queryset):
        count = 0
        for routine in queryset.exclude(master_video=""):
            queue_reference(routine_id=routine.pk)
            count += 1
        self.message_user(request, f"Referencias solicitadas para {count} rutinas.")


@admin.register(RoutineReference)
class RoutineReferenceAdmin(admin.ModelAdmin):
    list_display = ("routine", "version", "status", "engine_name", "created_at")
    list_filter = ("status", "engine_name")
    readonly_fields = ("created_at",)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_readonly_fields(self, request, obj=None):
        return tuple(field.name for field in self.model._meta.fields)
