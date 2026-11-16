from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    class Role(models.TextChoices):
        STUDENT = "STUDENT", "Estudiante"
        INSTRUCTOR = "INSTRUCTOR", "Instructor"
        ADMIN = "ADMIN", "Administrador"

    email = models.EmailField(unique=True)
    role = models.CharField(max_length=16, choices=Role.choices, default=Role.STUDENT)
    # Which version of the terms and privacy policy the person accepted at
    # sign-up, and when (settings.LEGAL_TERMS_VERSION). Blank: created before
    # acceptance existed, or by an administrator.
    terms_version = models.CharField("versión de términos aceptada", max_length=20, blank=True)
    terms_accepted_at = models.DateTimeField("términos aceptados el", null=True, blank=True)

    def __str__(self):
        return self.username

    def save(self, *args, **kwargs):
        # `createsuperuser` leaves the default role: a superuser is never
        # counted or treated as a student.
        if self.is_superuser and self.role == self.Role.STUDENT:
            self.role = self.Role.ADMIN
        # Instructors work in the Django Admin: the role alone opens it, so a
        # new instructor does not also need «Es staff» ticked. Never demotes.
        if self.role in (self.Role.INSTRUCTOR, self.Role.ADMIN):
            self.is_staff = True
            fields = kwargs.get("update_fields")
            if fields is not None and "role" in fields:
                kwargs["update_fields"] = {*fields, "is_staff"}
        super().save(*args, **kwargs)

    @property
    def manages_all_courses(self):
        """Superusers and the Administrator role see every course and student."""
        return self.is_superuser or self.role == self.Role.ADMIN

    @property
    def is_instructor(self):
        return self.role == self.Role.INSTRUCTOR
