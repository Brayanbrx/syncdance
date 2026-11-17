import secrets

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import F

# No 0/O or 1/I/L: the code is dictated in class and typed on a phone.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8


def new_join_code():
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def normalize_join_code(raw):
    """What a student types: any case, spaces or dashes in between."""
    return "".join(ch for ch in str(raw).upper() if ch.isalnum())


class Course(models.Model):
    """A group of students led by one instructor; students join with its code."""

    name = models.CharField("nombre", max_length=120)
    instructor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="courses_taught",
        limit_choices_to={"role__in": ("INSTRUCTOR", "ADMIN")},
    )
    join_code = models.CharField(
        "código para unirse", max_length=CODE_LENGTH, unique=True, default=new_join_code
    )
    accepts_students = models.BooleanField(
        "acepta alumnos nuevos",
        default=True,
        help_text="Desmarcar para cerrar las inscripciones con el código.",
    )
    # Routines the instructor published for this course: its students see
    # them even when they are not in the SyncDance catalog.
    published_routines = models.ManyToManyField(
        "routines.Routine",
        blank=True,
        related_name="published_in_courses",
        verbose_name="rutinas publicadas",
    )
    created_at = models.DateTimeField("creado", auto_now_add=True)

    class Meta:
        ordering = ("name",)
        verbose_name = "curso"
        verbose_name_plural = "cursos"

    def __str__(self):
        return self.name


class Enrollment(models.Model):
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="enrollments")
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="enrollments",
        verbose_name="alumno",
    )
    joined_at = models.DateTimeField("se unió", auto_now_add=True)

    class Meta:
        ordering = ("student__username",)
        verbose_name = "inscripción"
        verbose_name_plural = "inscripciones"
        constraints = [
            models.UniqueConstraint(fields=("course", "student"), name="unique_enrollment"),
        ]

    def __str__(self):
        return f"{self.student} en {self.course}"


class Assignment(models.Model):
    """A routine the course must dance, with a star goal in the dance game."""

    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="assignments")
    routine = models.ForeignKey(
        "routines.Routine",
        on_delete=models.PROTECT,
        related_name="assignments",
        verbose_name="rutina",
    )
    # Same scale as the phone: 3 stars passes a step of the learning path.
    target_stars = models.PositiveSmallIntegerField(
        "objetivo (estrellas)",
        default=3,
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        help_text="Estrellas del modo juego a velocidad normal.",
    )
    due_date = models.DateField("fecha límite", null=True, blank=True)
    instructions = models.TextField("indicaciones", blank=True, max_length=1000)
    created_at = models.DateTimeField("creada", auto_now_add=True)

    class Meta:
        ordering = (F("due_date").asc(nulls_last=True), "created_at")
        verbose_name = "tarea"
        verbose_name_plural = "tareas"
        constraints = [
            models.UniqueConstraint(fields=("course", "routine"), name="unique_course_routine"),
            models.CheckConstraint(
                condition=models.Q(target_stars__gte=1, target_stars__lte=5),
                name="assignment_target_stars_1_5",
            ),
        ]

    def __str__(self):
        return f"{self.routine} ({self.course})"


class SessionNote(models.Model):
    """Instructor observation on one synced practice; the student reads it."""

    session = models.ForeignKey(
        "training.DanceSession",
        on_delete=models.CASCADE,
        related_name="instructor_notes",
        verbose_name="práctica",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="session_notes",
        verbose_name="autor",
    )
    text = models.TextField("observación", max_length=1000)
    created_at = models.DateTimeField("fecha", auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        verbose_name = "observación del instructor"
        verbose_name_plural = "observaciones del instructor"

    def __str__(self):
        return f"{self.author} · {self.session_id}"

    def clean(self):
        super().clean()
        if not self.text.strip():
            raise ValidationError({"text": "Escribe la observación."})
        if self.author_id and self.session_id and not self.author.manages_all_courses:
            teaches = Enrollment.objects.filter(
                student_id=self.session.student_id, course__instructor_id=self.author_id
            ).exists()
            if not teaches:
                raise ValidationError("Solo puedes comentar prácticas de alumnos de tus cursos.")


class PracticeRating(models.Model):
    """The instructor's 1-5 judgement of one practice. Students do not see it:
    it measures how well the app's score agrees with the instructor (pilot)."""

    session = models.ForeignKey(
        "training.DanceSession",
        on_delete=models.CASCADE,
        related_name="ratings",
        verbose_name="práctica",
    )
    instructor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="practice_ratings",
        verbose_name="instructor",
    )
    rating = models.PositiveSmallIntegerField(
        "calificación", validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    created_at = models.DateTimeField("creada", auto_now_add=True)
    updated_at = models.DateTimeField("actualizada", auto_now=True)

    class Meta:
        ordering = ("-updated_at",)
        verbose_name = "calificación del instructor"
        verbose_name_plural = "calificaciones del instructor"
        constraints = [
            models.UniqueConstraint(
                fields=("session", "instructor"), name="one_rating_per_instructor"
            ),
            models.CheckConstraint(
                condition=models.Q(rating__gte=1, rating__lte=5), name="practice_rating_1_5"
            ),
        ]

    def __str__(self):
        return f"{self.instructor} · {self.session_id}: {self.rating}"
