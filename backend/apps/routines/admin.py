from django.contrib import admin

from .models import Routine, RoutineReference
from .reference_services import queue_reference


@admin.register(Routine)
class RoutineAdmin(admin.ModelAdmin):
    list_display = (
        "name",
        "instructor",
        "difficulty",
        "visibility",
        "published_at",
        "duration_ms",
        "is_active",
    )
    list_filter = ("visibility", "difficulty", "is_active")
    search_fields = ("name",)
    actions = ("generate_references",)

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        if obj.generator:
            return  # generated masters keep their exact choreography reference
        if not change or "master_video" in form.changed_data:
            obj.duration_ms = 0
            obj.save(update_fields=["duration_ms"])
            if obj.master_video:
                queue_reference(routine_id=obj.pk)

    @admin.action(description="Generar nueva referencia del video maestro", permissions=["change"])
    def generate_references(self, request, queryset):
        count = 0
        for routine in queryset.exclude(master_video="").filter(generator=""):
            queue_reference(routine_id=routine.pk)
            count += 1
        skipped = queryset.exclude(generator="").count()
        note = f" Omitidas {skipped} generadas desde coreografía." if skipped else ""
        self.message_user(request, f"Referencias solicitadas para {count} rutinas.{note}")


@admin.register(RoutineReference)
class RoutineReferenceAdmin(admin.ModelAdmin):
    list_display = (
        "routine",
        "version",
        "status",
        "engine_name",
        "created_at",
        "processing_time",
        "processing_task_id",
    )
    list_filter = ("status", "engine_name")
    search_fields = ("routine__name", "processing_task_id")
    readonly_fields = ("created_at",)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    @admin.display(description="Procesamiento")
    def processing_time(self, obj):
        """How long the worker took; «—» while queued or never started."""
        if not obj.processing_started_at:
            return "—"
        if not obj.processing_finished_at:
            return "en curso"
        seconds = (obj.processing_finished_at - obj.processing_started_at).total_seconds()
        return f"{seconds:.0f} s"

    def get_readonly_fields(self, request, obj=None):
        return tuple(field.name for field in self.model._meta.fields)
