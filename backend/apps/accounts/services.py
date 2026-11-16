import logging

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

from .models import User

logger = logging.getLogger(__name__)


class InvalidResetLink(Exception):
    """The link is malformed, expired, already used or for another account."""


class WrongPassword(Exception):
    """Deleting an account asks for its password again."""


class AccountProtected(Exception):
    """Other people depend on what the account owns; the message says what to do."""


def register_user(**validated_data) -> User:
    """A student who accepted the current terms and privacy policy."""
    return User.objects.create_user(
        role=User.Role.STUDENT,
        terms_version=settings.LEGAL_TERMS_VERSION,
        terms_accepted_at=timezone.now(),
        **validated_data,
    )


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


def deletion_blocker(user: User) -> str | None:
    """Why this account cannot delete itself, or None.

    Courses, routines and notes on students' practices belong to other people
    too (their models protect them): an administrator transfers them first.
    """
    if user.is_superuser:
        return (
            "Un superusuario no puede borrarse a sí mismo: pide a otro administrador "
            "que lo haga desde el Django Admin."
        )
    if user.courses_taught.exists() or user.routines.exists() or user.session_notes.exists():
        return (
            "Tu cuenta tiene cursos, rutinas u observaciones de alumnos a cargo. Pide a un "
            "administrador que los transfiera antes de borrarla."
        )
    return None


@transaction.atomic
def delete_account(*, user: User, password: str) -> None:
    """Delete the account and everything that is only its own: practices and
    their results, course memberships and old uploaded performance videos.
    Open sessions stop renewing at once.
    """
    if not user.check_password(password):
        raise WrongPassword
    blocker = deletion_blocker(user)
    if blocker:
        raise AccountProtected(blocker)
    videos = [p.video for p in user.performances.exclude(video="")]
    revoke_sessions(user)
    user_id = user.pk
    user.delete()

    def remove_files():
        for video in videos:
            video.storage.delete(video.name)

    # Files go only once the rows are gone for good.
    transaction.on_commit(remove_files)
    logger.info("account deleted", extra={"user_id": user_id, "files": len(videos)})


def revoke_sessions(user: User) -> int:
    """Blacklist every refresh token of the account: phones and the web panel
    must sign in again (access tokens still expire on their own, in minutes)."""
    pending = OutstandingToken.objects.filter(user=user, blacklistedtoken__isnull=True)
    created = BlacklistedToken.objects.bulk_create(
        [BlacklistedToken(token=token) for token in pending], ignore_conflicts=True
    )
    return len(created)
