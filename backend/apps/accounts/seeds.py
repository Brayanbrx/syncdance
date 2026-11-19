"""Seed steps that belong to accounts (see `manage.py seed`)."""

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import CommandError
from django.db.models import Q

from .models import User


def ensure_superadmin(say) -> None:
    """The platform's first superadministrator, from SEED_ADMIN_* (.env).

    Created once; afterwards it is never touched, so a password changed from
    the web or by email stays. An existing account that is not a superuser is
    never promoted: whoever registered that address first would get the
    platform.
    """
    email = settings.SEED_ADMIN_EMAIL
    if not email:
        say("= superadministrador: SEED_ADMIN_EMAIL vacío, no se crea.")
        return
    username = settings.SEED_ADMIN_USERNAME or email
    existing = User.objects.filter(Q(email__iexact=email) | Q(username__iexact=username)).first()
    if existing is not None:
        if existing.is_superuser:
            say(f"= superadministrador {existing.username}: ya existe.")
        else:
            say(
                f"! {existing.username} ya existe y no es superadministrador: no se promueve. "
                "Hazlo desde el panel si corresponde."
            )
        return
    password = settings.SEED_ADMIN_PASSWORD
    if not password:
        raise CommandError(
            "SEED_ADMIN_PASSWORD vacío: hace falta para crear el superadministrador."
        )
    user = User(
        username=username,
        email=email,
        role=User.Role.ADMIN,
        is_staff=True,
        is_superuser=True,
        is_active=True,
    )
    try:
        validate_password(password, user)
    except ValidationError as error:
        raise CommandError("SEED_ADMIN_PASSWORD no sirve: " + " ".join(error.messages)) from None
    user.set_password(password)
    user.save()
    say(f"+ superadministrador {username}: creado.")
