import hashlib
import logging

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from .models import AppRelease

logger = logging.getLogger(__name__)

MAX_APK_BYTES = 250 * 1024 * 1024
ZIP_MAGIC = b"PK\x03\x04"  # an APK is a zip archive


def _check_apk(upload):
    if not upload.name.lower().endswith(".apk"):
        raise ValidationError({"apk": "Sube el archivo .apk generado por Flutter."})
    if upload.size > MAX_APK_BYTES:
        raise ValidationError({"apk": "El APK supera 250 MB."})
    upload.seek(0)
    if upload.read(4) != ZIP_MAGIC:
        raise ValidationError({"apk": "El archivo no es un APK válido."})
    upload.seek(0)
    digest = hashlib.sha256()
    for chunk in upload.chunks():
        digest.update(chunk)
    upload.seek(0)
    return digest.hexdigest()


def create_release(
    *, actor, apk, version_name, version_code, notes="", min_android="7.0", is_published=False
):
    sha256 = _check_apk(apk)
    release = AppRelease(
        version_name=version_name,
        version_code=version_code,
        notes=notes,
        min_android=min_android,
        size_bytes=apk.size,
        sha256=sha256,
        is_published=is_published,
        published_at=timezone.now() if is_published else None,
        uploaded_by=actor,
    )
    release.apk.save(f"syncdance-{version_code}.apk", apk, save=False)
    release.save()
    logger.info(
        "app release uploaded",
        extra={"release_id": release.pk, "version_code": version_code, "user_id": actor.pk},
    )
    return release


def update_release(*, release, **changes):
    if "is_published" in changes and changes["is_published"] != release.is_published:
        release.published_at = timezone.now() if changes["is_published"] else None
    for field, value in changes.items():
        setattr(release, field, value)
    release.save()
    return release


def delete_release(*, release):
    if release.is_published:
        raise ValidationError("Despublica la versión antes de borrarla.")
    storage, name = release.apk.storage, release.apk.name
    release.delete()
    if name:
        transaction.on_commit(lambda: storage.delete(name))


# --- Users -----------------------------------------------------------------


def _guard_target(*, actor, user):
    if user.is_superuser and not actor.is_superuser:
        raise PermissionDenied("Solo un superusuario puede modificar a otro superusuario.")


def _validated_password(password, user):
    try:
        validate_password(password, user=user)
    except DjangoValidationError as exc:
        raise ValidationError({"password": list(exc.messages)}) from exc


def create_user(*, actor, password, role, **fields):
    User = get_user_model()
    candidate = User(role=role, **fields)
    _validated_password(password, candidate)
    user = User.objects.create_user(password=password, role=role, **fields)
    logger.info(
        "user created from panel",
        extra={"user_id": user.pk, "role": role, "actor_id": actor.pk},
    )
    return user


def update_user(*, actor, user, **changes):
    """Role and access changes. Nobody locks themselves out, and a student
    loses access to the Django Admin with the role."""
    _guard_target(actor=actor, user=user)
    if user.pk == actor.pk and (
        ("role" in changes and changes["role"] != user.role)
        or ("is_active" in changes and not changes["is_active"])
    ):
        raise ValidationError("No puedes cambiar tu propio rol ni desactivar tu cuenta.")
    for field, value in changes.items():
        setattr(user, field, value)
    if user.role == user.Role.STUDENT and not user.is_superuser:
        user.is_staff = False
    user.save()
    if {"role", "is_active"} & changes.keys():
        logger.info(
            "user access changed from panel",
            extra={
                "user_id": user.pk,
                "role": user.role,
                "is_active": user.is_active,
                "actor_id": actor.pk,
            },
        )
    return user


def set_password(*, actor, user, password):
    _guard_target(actor=actor, user=user)
    _validated_password(password, user)
    user.set_password(password)
    user.save(update_fields=["password"])
    logger.info("password reset from panel", extra={"user_id": user.pk, "actor_id": actor.pk})
