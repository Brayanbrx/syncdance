import hashlib
import logging

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import F
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError

from apps.routines.models import Routine

from .apk import apk_versions
from .models import AppErrorReport, AppRelease

logger = logging.getLogger(__name__)


class Conflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_code = "conflict"


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


def _declared_versions(apk, version_code, version_name):
    """The versions the APK itself declares; typed values must agree: a wrong
    code would make every phone see an update forever, or never."""
    declared = apk_versions(apk)
    if declared is None:
        raise ValidationError(
            {"apk": "No se pudo leer la versión del APK. Súbelo tal como lo genera Flutter."}
        )
    code, name = declared
    if version_code is not None and version_code != code:
        raise ValidationError(
            {"version_code": f"El APK es la versión {name} con código {code}, no {version_code}."}
        )
    if version_name and name and version_name != name:
        raise ValidationError({"version_name": f"El APK es la versión {name}, no {version_name}."})
    if AppRelease.objects.filter(version_code=code).exists():
        message = f"Ya hay un APK con el código {code}: compila uno con un código mayor."
        raise ValidationError({"version_code": message})
    return code, version_name or name or str(code)


def create_release(
    *,
    actor,
    apk,
    version_name=None,
    version_code=None,
    notes="",
    min_android="7.0",
    is_published=False,
):
    sha256 = _check_apk(apk)
    version_code, version_name = _declared_versions(apk, version_code, version_name)
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


def _pending_proposal(routine):
    """Lock the routine and check it still waits for review: two admins may
    answer at once, or the instructor may have withdrawn it meanwhile."""
    routine = Routine.objects.select_for_update().get(pk=routine.pk)
    if routine.catalog_review != Routine.CatalogReview.PENDING:
        raise Conflict("Esta propuesta ya no está pendiente.")
    return routine


@transaction.atomic
def approve_for_catalog(*, actor, routine):
    routine = _pending_proposal(routine)
    if not routine.is_published or not routine.is_active:
        raise Conflict("La rutina ya no está publicada: su instructor la retiró.")
    routine.visibility = Routine.Visibility.CATALOG
    routine.catalog_review = Routine.CatalogReview.APPROVED
    routine.catalog_reviewed_at = timezone.now()
    routine.catalog_reviewed_by = actor
    routine.catalog_review_note = ""
    routine.save(
        update_fields=[
            "visibility",
            "catalog_review",
            "catalog_reviewed_at",
            "catalog_reviewed_by",
            "catalog_review_note",
        ]
    )
    logger.info("catalog proposal approved", extra={"routine_id": routine.pk, "user_id": actor.pk})
    return routine


@transaction.atomic
def reject_for_catalog(*, actor, routine, note):
    note = (note or "").strip()
    if not note:
        raise ValidationError({"note": ["Explica al instructor por qué no se acepta."]})
    routine = _pending_proposal(routine)
    routine.catalog_review = Routine.CatalogReview.REJECTED
    routine.catalog_reviewed_at = timezone.now()
    routine.catalog_reviewed_by = actor
    routine.catalog_review_note = note
    routine.save(
        update_fields=[
            "catalog_review",
            "catalog_reviewed_at",
            "catalog_reviewed_by",
            "catalog_review_note",
        ]
    )
    logger.info("catalog proposal rejected", extra={"routine_id": routine.pk, "user_id": actor.pk})
    return routine


def report_app_error(*, app_version, kind, message="", stack="", os_version=""):
    """Count one more occurrence of an error, grouped by version, kind and
    where it happened (the first lines of the stack)."""
    top = "\n".join(stack.splitlines()[:3])
    fingerprint = hashlib.sha256(f"{app_version}|{kind}|{top}".encode()).hexdigest()
    now = timezone.now()
    updated = AppErrorReport.objects.filter(fingerprint=fingerprint).update(
        count=F("count") + 1, last_seen=now
    )
    if updated:
        return
    try:
        with transaction.atomic():
            AppErrorReport.objects.create(
                fingerprint=fingerprint,
                app_version=app_version,
                os_version=os_version,
                kind=kind,
                message=message,
                stack=stack,
                last_seen=now,
            )
    except IntegrityError:  # the same error arrived twice at once
        AppErrorReport.objects.filter(fingerprint=fingerprint).update(
            count=F("count") + 1, last_seen=now
        )
