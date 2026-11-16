from django.db.models import Exists, OuterRef, Q

from .models import Routine


def get_routines_for_user(*, user):
    """Routines an account may list, download and practice.

    A student sees active, published routines that are in the SyncDance catalog
    or belong to one of their courses (published there or assigned as a task).
    An instructor's other routines, drafts included, stay private. This also
    scopes the reference and video downloads and the practice uploads.
    """
    queryset = Routine.objects.select_related("instructor")
    if not user.is_authenticated:
        return queryset.none()
    if user.role == user.Role.STUDENT:
        return queryset.filter(
            Q(visibility=Routine.Visibility.CATALOG) | in_courses_of(user),
            is_active=True,
            published_at__isnull=False,
        )
    if user.role == user.Role.INSTRUCTOR:
        return queryset.filter(instructor=user)
    return queryset


def in_courses_of(student) -> Q:
    """Published in, or assigned to, a course the student belongs to."""
    from apps.coaching.models import Assignment, Course

    published = Course.published_routines.through.objects.filter(
        routine_id=OuterRef("pk"), course__enrollments__student=student
    )
    assigned = Assignment.objects.filter(
        routine_id=OuterRef("pk"), course__enrollments__student=student
    )
    return Q(Exists(published)) | Q(Exists(assigned))
