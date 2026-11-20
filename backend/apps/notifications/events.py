"""Who is told what, for each event of the platform.

Each function builds the message and calls `services.notify`; the dedupe
keys make every one of them safe to call twice for the same event. Routes
are screens of the phone app; events the instructor handles on the web
(the studio, the error reports) have no route.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone

from .models import Notification
from .services import notify

Kind = Notification.Kind


def _stars(count):
    return "★" * count


def _routine_route(routine):
    return "/singing" if routine.is_singing else "/routines"


def assignment_created(assignment):
    course = assignment.course
    due = f" · vence el {assignment.due_date:%d/%m}" if assignment.due_date is not None else ""
    notify(
        [enrollment.student for enrollment in course.enrollments.select_related("student")],
        kind=Kind.ASSIGNMENT_NEW,
        title=f"Nueva tarea en {course.name}",
        body=f"{assignment.routine.name}: meta {_stars(assignment.target_stars)}{due}",
        route="/courses",
        dedupe_key=f"assignment:{assignment.pk}",
    )


def assignments_due_tomorrow(*, today=None):
    """Remind the students who have not met the goal yet. Returns how many
    were told."""
    from apps.coaching.models import Assignment
    from apps.coaching.selectors import RoutineEvidence, assignment_status, routine_evidence

    today = today or timezone.localdate()
    told = 0
    due = Assignment.objects.filter(due_date=today + timedelta(days=1)).select_related(
        "course", "routine"
    )
    for assignment in due:
        students = [
            enrollment.student
            for enrollment in assignment.course.enrollments.select_related("student")
        ]
        evidence = routine_evidence(
            student_ids=[student.pk for student in students],
            routine_ids=[assignment.routine_id],
        )
        pending = [
            student
            for student in students
            if not assignment_status(
                assignment,
                evidence.get(
                    (student.pk, assignment.routine_id),
                    RoutineEvidence(best_stars=None, practices=0, last_practice_at=None),
                ),
                today=today,
            ).completed
        ]
        told += len(
            notify(
                pending,
                kind=Kind.ASSIGNMENT_DUE,
                title="Mañana vence una tarea",
                body=(
                    f"{assignment.routine.name} ({assignment.course.name}): "
                    f"consigue {_stars(assignment.target_stars)} en el modo juego"
                ),
                route="/courses",
                dedupe_key=f"due:{assignment.pk}:{assignment.due_date:%Y%m%d}",
            )
        )
    return told


def session_note_created(note):
    session = note.session
    text = note.text.strip()
    notify(
        [session.student],
        kind=Kind.SESSION_NOTE,
        title=f"{note.author} comentó tu práctica",
        body=f"{session.routine.name}: {text[:200]}",
        route="/courses",
        dedupe_key=f"note:{note.pk}",
    )


def game_saved(game):
    """A synced game that meets a goal of the student's courses tells the
    instructor, the first time only. Slower practice never counts."""
    from apps.coaching.models import Assignment

    session = game.session
    if session.playback_speed != 1.0:
        return
    stars = game.stars
    met = Assignment.objects.filter(
        routine_id=session.routine_id,
        course__enrollments__student=session.student,
        target_stars__lte=stars,
    ).select_related("course__instructor", "routine")
    for assignment in met:
        notify(
            [assignment.course.instructor],
            kind=Kind.ASSIGNMENT_DONE,
            title=f"{session.student} cumplió una tarea",
            body=(
                f"{assignment.routine.name} en {assignment.course.name}: "
                f"{_stars(stars)} (meta {_stars(assignment.target_stars)})"
            ),
            dedupe_key=f"done:{assignment.pk}:{session.student_id}",
        )


def routine_entered_catalog(routine):
    """Every student hears of a new routine in the free catalog, once."""
    if not routine.is_published or not routine.is_active:
        return
    students = get_user_model().objects.filter(role="STUDENT", is_active=True)
    kind_label = "canto" if routine.is_singing else "baile"
    notify(
        students.exclude(pk=routine.instructor_id),
        kind=Kind.CATALOG_NEW,
        title="Rutina nueva en el catálogo",
        body=f"{routine.name} · {kind_label} · {routine.get_difficulty_display()}",
        route=_routine_route(routine),
        dedupe_key=f"catalog:{routine.pk}",
    )


def catalog_reviewed(routine):
    approved = routine.catalog_review == routine.CatalogReview.APPROVED
    reviewed = routine.catalog_reviewed_at or timezone.now()
    notify(
        [routine.instructor],
        kind=Kind.CATALOG_REVIEW,
        title=(
            "Tu rutina entró al catálogo"
            if approved
            else "Tu rutina no fue aceptada en el catálogo"
        ),
        body=(
            f"{routine.name} ya está disponible para todos los alumnos."
            if approved
            else f"{routine.name}: {routine.catalog_review_note[:200]}"
        ),
        dedupe_key=f"review:{routine.pk}:{reviewed:%Y%m%d%H%M%S}",
    )


def release_published(release):
    """Phones outside Google Play learn of a new APK this way."""
    users = get_user_model().objects.filter(is_active=True, push_devices__isnull=False).distinct()
    notify(
        users,
        kind=Kind.APP_RELEASE,
        title="Hay una versión nueva de SyncDance",
        body=f"Versión {release.version_name}: abre la app para actualizarla.",
        route="/home",
        dedupe_key=f"release:{release.pk}",
    )


def reference_finished(reference):
    """The instructor who uploaded a master learns when it is ready or why it
    failed. Installed catalogs (catalog_key) are nobody's upload."""
    routine = reference.routine
    if routine.catalog_key:
        return
    ready = reference.status == reference.Status.READY
    notify(
        [routine.instructor],
        kind=Kind.REFERENCE_READY if ready else Kind.REFERENCE_FAILED,
        title=(
            f"«{routine.name}» está lista para publicar"
            if ready
            else f"No se pudo procesar «{routine.name}»"
        ),
        body=(
            "El video del maestro terminó de procesarse. Publícala desde el estudio."
            if ready
            else (reference.processing_error or "Revisa el video en el estudio.")[:300]
        ),
        dedupe_key=f"reference:{reference.pk}",
    )


def app_error_reported(report):
    """Only the first occurrence of an error: repeats only raise its count."""
    admins = get_user_model().objects.filter(Q(role="ADMIN") | Q(is_superuser=True), is_active=True)
    notify(
        admins,
        kind=Kind.APP_ERROR,
        title=f"Error nuevo en la app {report.app_version}",
        body=(report.message or report.kind)[:300],
        dedupe_key=f"error:{report.pk}",
    )
