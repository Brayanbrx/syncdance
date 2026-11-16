import logging

from django.db import IntegrityError, transaction

from .models import Course, Enrollment, new_join_code, normalize_join_code

logger = logging.getLogger(__name__)


class InvalidJoinCode(Exception):
    """Unknown code or a course that no longer accepts students."""


def join_course(*, student, raw_code):
    """Enroll with a course code. Returns (course, created); joining twice is
    harmless so a retried request from the phone gets the same answer."""
    code = normalize_join_code(raw_code)
    course = Course.objects.filter(join_code=code, accepts_students=True).first()
    if course is None:
        raise InvalidJoinCode
    try:
        with transaction.atomic():
            _, created = Enrollment.objects.get_or_create(course=course, student=student)
    except IntegrityError:
        created = False  # a concurrent duplicate request won the insert
    if created:
        logger.info("student joined course", extra={"course_id": course.pk, "user_id": student.pk})
    return course, created


def leave_course(*, student, course):
    deleted, _ = Enrollment.objects.filter(course=course, student=student).delete()
    if deleted:
        logger.info("student left course", extra={"course_id": course.pk, "user_id": student.pk})
    return bool(deleted)


def regenerate_join_code(*, course):
    """A leaked code stops working; already enrolled students stay."""
    for _ in range(5):
        candidate = new_join_code()
        if not Course.objects.filter(join_code=candidate).exists():
            course.join_code = candidate
            course.save(update_fields=["join_code"])
            return candidate
    raise RuntimeError("No se pudo generar un código único.")
