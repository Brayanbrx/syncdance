import logging

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.db import transaction
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

from .models import User

logger = logging.getLogger(__name__)


class InvalidResetLink(Exception):
    """The link is malformed, expired, already used or for another account."""


def register_user(**validated_data) -> User:
    return User.objects.create_user(role=User.Role.STUDENT, **validated_data)


def request_password_reset(*, email: str) -> None:
    """Queue an email with a single-use link to choose a new password.

    Silent when no active account has that address, and the mail leaves from
    the worker: the answer is the same and takes as long whether or not the
    address is registered, even if the mail server is down.
    """
    from .tasks import send_password_reset

    user = User.objects.filter(email__iexact=email.strip(), is_active=True).first()
    if user is None or not user.has_usable_password():
        return
    send_password_reset.delay(user.pk)


def send_password_reset_email(user: User) -> None:
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    link = f"{settings.PUBLIC_WEB_URL}/cuenta/restablecer?uid={uid}&token={token}"
    hours = settings.PASSWORD_RESET_TIMEOUT // 3600
    send_mail(
        subject="Cambiar tu contraseña de SyncDance",
        message=(
            f"Hola, {user.first_name or user.username}:\n\n"
            f"Recibimos un pedido para cambiar la contraseña de tu cuenta de SyncDance "
            f"(usuario {user.username}).\n\n"
            f"Para elegir una nueva, abre este enlace. Vale por {hours} horas y sirve "
            f"una sola vez:\n{link}\n\n"
            "Si no lo pediste, ignora este correo: tu contraseña sigue igual.\n"
        ),
        from_email=None,
        recipient_list=[user.email],
    )
    logger.info("password reset link sent", extra={"user_id": user.pk})


@transaction.atomic
def reset_password(*, uid: str, token: str, password: str) -> User:
    """Set the new password and close every open session of the account.

    The token embeds the current password hash: once used it stops working.
    Raises InvalidResetLink, or Django's ValidationError for a weak password.
    """
    try:
        user = User.objects.get(pk=force_str(urlsafe_base64_decode(uid)), is_active=True)
    except (ValueError, TypeError, OverflowError, User.DoesNotExist) as exc:
        raise InvalidResetLink from exc
    if not default_token_generator.check_token(user, token):
        raise InvalidResetLink
    validate_password(password, user=user)
    user.set_password(password)
    user.save(update_fields=["password"])
    revoke_sessions(user)
    logger.info("password reset", extra={"user_id": user.pk})
    return user


def revoke_sessions(user: User) -> int:
    """Blacklist every refresh token of the account: phones and the web panel
    must sign in again (access tokens still expire on their own, in minutes)."""
    pending = OutstandingToken.objects.filter(user=user, blacklistedtoken__isnull=True)
    created = BlacklistedToken.objects.bulk_create(
        [BlacklistedToken(token=token) for token in pending], ignore_conflicts=True
    )
    return len(created)
