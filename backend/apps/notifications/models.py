from django.conf import settings
from django.db import models
from django.db.models import Q


class PushDevice(models.Model):
    """One phone that may receive push messages (its FCM registration token).

    A token belongs to the account last signed in on that phone: signing in
    with another account moves it, and signing out removes it.
    """

    class Platform(models.TextChoices):
        ANDROID = "ANDROID", "Android"
        IOS = "IOS", "iOS"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="push_devices"
    )
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=8, choices=Platform.choices, default=Platform.ANDROID)
    app_version = models.CharField(max_length=32, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "dispositivo"
        verbose_name_plural = "dispositivos"

    def __str__(self):
        return f"{self.user} · {self.get_platform_display()}"


class Notification(models.Model):
    """What a person was told. It is the in-app inbox and the push log: the
    push is a copy of this row sent to the person's phones."""

    class Kind(models.TextChoices):
        ASSIGNMENT_NEW = "ASSIGNMENT_NEW", "Nueva tarea"
        ASSIGNMENT_DUE = "ASSIGNMENT_DUE", "Tarea por vencer"
        ASSIGNMENT_DONE = "ASSIGNMENT_DONE", "Tarea cumplida por un alumno"
        SESSION_NOTE = "SESSION_NOTE", "Observación del instructor"
        CATALOG_NEW = "CATALOG_NEW", "Rutina nueva en el catálogo"
        CATALOG_REVIEW = "CATALOG_REVIEW", "Revisión para el catálogo"
        APP_RELEASE = "APP_RELEASE", "Nueva versión de la app"
        REFERENCE_READY = "REFERENCE_READY", "Video del maestro procesado"
        REFERENCE_FAILED = "REFERENCE_FAILED", "Video del maestro con error"
        APP_ERROR = "APP_ERROR", "Error nuevo en la app"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    kind = models.CharField(max_length=24, choices=Kind.choices)
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=300)
    # Screen of the phone app opened on tap (e.g. "/courses"); blank: none.
    route = models.CharField(max_length=120, blank=True)
    # The same event never notifies the same person twice (signals and the
    # periodic due-date check may run more than once).
    dedupe_key = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)
    pushed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at", "-id")
        verbose_name = "notificación"
        verbose_name_plural = "notificaciones"
        constraints = [
            models.UniqueConstraint(
                fields=("user", "dedupe_key"),
                condition=~Q(dedupe_key=""),
                name="unique_notification_per_event",
            ),
        ]
        indexes = [models.Index(fields=("user", "read_at"))]

    def __str__(self):
        return f"{self.user}: {self.title}"
