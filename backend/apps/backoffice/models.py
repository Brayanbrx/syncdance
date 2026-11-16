from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class AppRelease(models.Model):
    """An Android build offered on the landing page. People download the
    published one with the highest version code."""

    version_name = models.CharField("versión", max_length=32, help_text="Por ejemplo 1.2.0")
    version_code = models.PositiveIntegerField(
        "código de versión",
        unique=True,
        validators=[MinValueValidator(1)],
        help_text="El número tras el «+» en pubspec.yaml; sube en cada APK.",
    )
    apk = models.FileField("APK", upload_to="releases/")
    size_bytes = models.PositiveBigIntegerField("tamaño (bytes)", default=0)
    sha256 = models.CharField("SHA-256", max_length=64, blank=True)
    notes = models.TextField("novedades", blank=True, max_length=2000)
    min_android = models.CharField("Android mínimo", max_length=8, default="7.0")
    is_published = models.BooleanField("publicada", default=False)
    published_at = models.DateTimeField("publicada el", null=True, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="app_releases",
    )
    created_at = models.DateTimeField("subida", auto_now_add=True)

    class Meta:
        ordering = ("-version_code",)
        verbose_name = "versión de la app"
        verbose_name_plural = "versiones de la app"

    def __str__(self):
        return f"SyncDance {self.version_name} ({self.version_code})"

    @property
    def download_name(self):
        return f"SyncDance-{self.version_name}.apk"
