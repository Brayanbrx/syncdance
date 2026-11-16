from django.contrib import admin
from django.core.exceptions import PermissionDenied
from django.db.models import Count
from django.shortcuts import get_object_or_404
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils.html import format_html

from apps.routines.models import Routine

from .models import Assignment, Course, Enrollment, SessionNote
from .selectors import course_progress, courses_managed_by
from .services import regenerate_join_code


def can_coach(user):
    """The role opens the courses: instructors need no Django model
    permissions. Superusers and the Administrator role see every course."""
    return user.is_active and user.is_staff and (user.manages_all_courses or user.is_instructor)


def _stars(count):
    return "★" * count + "☆" * (5 - count)


class CourseInlineAccess:
    """Inline rows of a course follow the course: whoever may edit it."""

    def has_view_permission(self, request, obj=None):
        return can_coach(request.user)

    def has_add_permission(self, request, obj=None):
        return can_coach(request.user)

    def has_change_permission(self, request, obj=None):
        return can_coach(request.user)

    def has_delete_permission(self, request, obj=None):
        return can_coach(request.user)


class AssignmentInline(CourseInlineAccess, admin.TabularInline):
    model = Assignment
    extra = 1
    fields = ("routine", "target_stars", "due_date", "instructions")

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "routine":
            # Students only see active routines in the app.
            kwargs["queryset"] = Routine.objects.filter(is_active=True).order_by("name")
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


class EnrollmentInline(CourseInlineAccess, admin.TabularInline):
    model = Enrollment
    extra = 0
    fields = ("student", "joined_at")
    readonly_fields = ("student", "joined_at")
    verbose_name_plural = "alumnos inscritos (se unen desde la app con el código)"

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    change_form_template = "admin/coaching/course/change_form.html"
    list_display = (
        "name",
        "instructor",
        "join_code",
        "students",
        "assignment_count",
        "accepts_students",
        "progress_link",
    )
    list_filter = ("accepts_students",)
    search_fields = ("name", "join_code")
    readonly_fields = ("join_code", "created_at")
    inlines = (AssignmentInline, EnrollmentInline)
    actions = ("new_codes",)

    def get_queryset(self, request):
        return courses_managed_by(user=request.user).annotate(
            student_total=Count("enrollments", distinct=True),
            assignment_total=Count("assignments", distinct=True),
        )

    def _owns(self, request, obj):
        user = request.user
        return obj is None or user.manages_all_courses or obj.instructor_id == user.pk

    def has_module_permission(self, request):
        return can_coach(request.user)

    def has_view_permission(self, request, obj=None):
        return can_coach(request.user) and self._owns(request, obj)

    def has_add_permission(self, request):
        return can_coach(request.user)

    def has_change_permission(self, request, obj=None):
        return can_coach(request.user) and self._owns(request, obj)

    def has_delete_permission(self, request, obj=None):
        return can_coach(request.user) and self._owns(request, obj)

    def get_fields(self, request, obj=None):
        fields = ["name", "accepts_students", "join_code", "created_at"]
        if request.user.manages_all_courses:
            fields.insert(1, "instructor")
        return fields

    def save_model(self, request, obj, form, change):
        if not request.user.manages_all_courses:
            obj.instructor = request.user  # an instructor's courses are always their own
        super().save_model(request, obj, form, change)

    @admin.display(description="Alumnos", ordering="student_total")
    def students(self, obj):
        return obj.student_total

    @admin.display(description="Tareas", ordering="assignment_total")
    def assignment_count(self, obj):
        return obj.assignment_total

    @admin.display(description="Progreso")
    def progress_link(self, obj):
        url = reverse("admin:coaching_course_progress", args=[obj.pk])
        return format_html('<a href="{}">Ver progreso</a>', url)

    @admin.action(description="Generar un código nuevo (el anterior deja de servir)")
    def new_codes(self, request, queryset):
        for course in queryset:
            if not self.has_change_permission(request, course):
                raise PermissionDenied
            regenerate_join_code(course=course)
        self.message_user(request, f"Códigos nuevos para {queryset.count()} cursos.")

    def get_urls(self):
        return [
            path(
                "<int:course_id>/progreso/",
                self.admin_site.admin_view(self.progress_view),
                name="coaching_course_progress",
            ),
            *super().get_urls(),
        ]

    def progress_view(self, request, course_id):
        """Per student, the best stars of every assignment against its goal."""
        course = get_object_or_404(courses_managed_by(user=request.user), pk=course_id)
        if not self.has_view_permission(request, course):
            raise PermissionDenied
        assignments, rows = course_progress(course=course)
        cells = [
            {
                "student": row["student"],
                "completed": row["completed"],
                "cells": [
                    {
                        "stars": None
                        if status.evidence.best_stars is None
                        else _stars(status.evidence.best_stars),
                        "completed": status.completed,
                        "overdue": status.overdue,
                        "practices": status.evidence.practices,
                    }
                    for status in row["statuses"]
                ],
            }
            for row in rows
        ]
        context = {
            **self.admin_site.each_context(request),
            "title": f"Progreso del curso «{course.name}»",
            "opts": self.model._meta,
            "course": course,
            "assignments": assignments,
            "rows": cells,
        }
        return TemplateResponse(request, "admin/coaching/course/progress.html", context)


class SessionNoteInline(admin.StackedInline):
    """Shown on a practice in «Sesiones de baile»: the instructor writes an
    observation the student reads in the app. Notes stay as written."""

    model = SessionNote
    extra = 1
    fields = ("text", "author", "created_at")
    readonly_fields = ("author", "created_at")

    def has_view_permission(self, request, obj=None):
        return can_coach(request.user) or super().has_view_permission(request, obj)

    def has_add_permission(self, request, obj=None):
        return can_coach(request.user)

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return request.user.manages_all_courses
