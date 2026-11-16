import csv

from django.contrib import admin
from django.core.exceptions import PermissionDenied
from django.http import HttpResponse
from django.template.response import TemplateResponse
from django.urls import path
from django.utils import timezone

from apps.coaching.admin import SessionNoteInline, can_coach
from apps.coaching.models import SessionNote
from apps.coaching.selectors import students_of

from .models import (
    DanceSession,
    ErrorEvent,
    FeedbackCount,
    GameResult,
    SegmentScore,
    TimelineSegment,
)
from .selectors import MIN_PROGRESS_COVERAGE, get_student_progress


class CoachCanView:
    """Instructors read the results of their students without model permissions."""

    def has_view_permission(self, request, obj=None):
        return can_coach(request.user) or super().has_view_permission(request, obj)


class SegmentScoreInline(CoachCanView, admin.TabularInline):
    model = SegmentScore
    extra = 0
    can_delete = False
    readonly_fields = ("segment", "score", "coverage")

    def has_add_permission(self, request, obj=None):
        return False


class TimelineSegmentInline(CoachCanView, admin.TabularInline):
    model = TimelineSegment
    extra = 0
    can_delete = False
    readonly_fields = ("start_ms", "end_ms", "evaluated_ms", "score")

    def has_add_permission(self, request, obj=None):
        return False


class FeedbackCountInline(CoachCanView, admin.TabularInline):
    model = FeedbackCount
    extra = 0
    can_delete = False
    readonly_fields = ("code", "region", "message", "count", "max_severity")

    def has_add_permission(self, request, obj=None):
        return False


class ErrorEventInline(CoachCanView, admin.TabularInline):
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


class GameResultInline(CoachCanView, admin.StackedInline):
    model = GameResult
    extra = 0
    can_delete = False
    readonly_fields = (
        "version",
        "points",
        "max_points",
        "max_combo",
        "perfect",
        "great",
        "good",
        "miss",
        "unrated",
    )

    def has_add_permission(self, request, obj=None):
        return False


class KindFilter(admin.SimpleListFilter):
    title = "modo"
    parameter_name = "modo"

    def lookups(self, request, model_admin):
        return (("juego", "Juego («Bailar»)"), ("practica", "Práctica con cámara"))

    def queryset(self, request, queryset):
        if self.value() == "juego":
            return queryset.filter(game__isnull=False)
        if self.value() == "practica":
            return queryset.filter(game__isnull=True)
        return queryset


def _game(session):
    return getattr(session, "game", None)


def _cell(text):
    """Names may start with + - @ (Django usernames allow them) or =: a
    spreadsheet would run them as formulas, so they are kept as text."""
    return f"'{text}" if text[:1] in ("=", "+", "-", "@") else text


def _stars(count):
    return "★" * count + "☆" * (5 - count)


@admin.register(DanceSession)
class DanceSessionAdmin(admin.ModelAdmin):
    change_list_template = "admin/training/dancesession/change_list.html"
    list_display = (
        "started_at",
        "student",
        "routine",
        "kind",
        "stars",
        "points",
        "similarity",
        "coverage",
        "follow_mode",
        "playback_speed",
    )
    list_select_related = ("student", "routine", "game")
    list_filter = (KindFilter, "routine", "follow_mode", "playback_speed")
    search_fields = ("student__username", "routine__name")
    date_hierarchy = "started_at"
    inlines = (
        GameResultInline,
        TimelineSegmentInline,
        FeedbackCountInline,
        SegmentScoreInline,
        ErrorEventInline,
        SessionNoteInline,
    )
    readonly_fields = tuple(field.name for field in DanceSession._meta.fields)

    @staticmethod
    def _limited(user):
        """An instructor reviews only the students of their courses."""
        return user.is_instructor and not user.manages_all_courses

    def _students(self, request):
        return students_of(user=request.user) if self._limited(request.user) else None

    def get_queryset(self, request):
        queryset = super().get_queryset(request)
        students = self._students(request)
        return queryset if students is None else queryset.filter(student__in=students)

    def _coaches(self, request, obj):
        if not can_coach(request.user):
            return False
        students = self._students(request)
        return obj is None or students is None or students.filter(pk=obj.student_id).exists()

    def has_module_permission(self, request):
        return super().has_module_permission(request) or can_coach(request.user)

    def has_view_permission(self, request, obj=None):
        if self._limited(request.user):
            return self._coaches(request, obj)
        return super().has_view_permission(request, obj) or self._coaches(request, obj)

    def has_change_permission(self, request, obj=None):
        # Every session field is read-only: «change» only adds observations.
        if self._limited(request.user):
            return self._coaches(request, obj)
        return super().has_change_permission(request, obj) or self._coaches(request, obj)

    def has_delete_permission(self, request, obj=None):
        return not self._limited(request.user) and super().has_delete_permission(request, obj)

    def has_add_permission(self, request):
        return False

    def save_formset(self, request, form, formset, change):
        if formset.model is not SessionNote:
            return super().save_formset(request, form, formset, change)
        for note in formset.save(commit=False):
            if note.author_id is None:
                note.author = request.user
            note.save()
        for note in formset.deleted_objects:
            note.delete()

    @admin.display(description="Modo")
    def kind(self, obj):
        return "Juego" if _game(obj) else "Práctica"

    @admin.display(description="Estrellas")
    def stars(self, obj):
        game = _game(obj)
        return _stars(game.stars) if game else "—"

    @admin.display(description="Puntos")
    def points(self, obj):
        game = _game(obj)
        return f"{game.points}/{game.max_points}" if game else "—"

    @admin.display(description="Similitud", ordering="pose_score")
    def similarity(self, obj):
        # Without evaluated time there is no score: never shown as zero.
        return "—" if obj.pose_score is None else f"{obj.pose_score:.0f}"

    @admin.display(description="Cobertura", ordering="quality_ratio")
    def coverage(self, obj):
        return "—" if obj.quality_ratio is None else f"{obj.quality_ratio:.0%}"

    def get_urls(self):
        return [
            path(
                "progreso/",
                self.admin_site.admin_view(self.progress_view),
                name="training_dancesession_progress",
            ),
            path(
                "progreso/csv/",
                self.admin_site.admin_view(self.progress_csv),
                name="training_dancesession_progress_csv",
            ),
            *super().get_urls(),
        ]

    def progress_view(self, request):
        """Instructor summary per student and routine (read-only)."""
        if not self.has_view_permission(request):
            raise PermissionDenied
        rows = [
            {**row, "stars": None if row["best_stars"] is None else _stars(row["best_stars"])}
            for row in get_student_progress(students=self._students(request))
        ]
        context = {
            **self.admin_site.each_context(request),
            "title": "Progreso por alumno",
            "opts": self.model._meta,
            "rows": rows,
            "min_coverage": f"{MIN_PROGRESS_COVERAGE:.0%}",
        }
        return TemplateResponse(request, "admin/training/dancesession/progress.html", context)

    def progress_csv(self, request):
        """The same summary for a spreadsheet: `;` and a BOM so Excel in
        Spanish opens it in columns with accents intact."""
        if not self.has_view_permission(request):
            raise PermissionDenied
        response = HttpResponse(content_type="text/csv; charset=utf-8")
        response["Content-Disposition"] = 'attachment; filename="progreso-alumnos.csv"'
        response.write("﻿")
        writer = csv.writer(response, delimiter=";")
        writer.writerow(
            [
                "Alumno",
                "Rutina",
                "Prácticas",
                "Partidas",
                "Mejor similitud",
                "Mejores estrellas",
                "Última práctica",
            ]
        )
        for row in get_student_progress(students=self._students(request)):
            writer.writerow(
                [
                    _cell(row["student__username"]),
                    _cell(row["routine__name"]),
                    row["practices"],
                    row["games"],
                    "" if row["best_score"] is None else round(row["best_score"]),
                    "" if row["best_stars"] is None else row["best_stars"],
                    timezone.localtime(row["last_practice"]).strftime("%d/%m/%Y %H:%M"),
                ]
            )
        return response
