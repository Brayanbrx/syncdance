import logging

from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import Notification, PushDevice

logger = logging.getLogger(__name__)


def notify(users, *, kind, title, body, route="", dedupe_key=""):
    """Save one notification per person and push it once the transaction
    commits. With a `dedupe_key`, a person already told is skipped.
    Returns the new notifications."""
    users = [user for user in users if user is not None and user.is_active]
    if not users:
        return []
    if dedupe_key:
        told = set(
            Notification.objects.filter(user__in=users, dedupe_key=dedupe_key).values_list(
                "user_id", flat=True
            )
        )
        users = [user for user in users if user.pk not in told]
    created = []
    for user in {user.pk: user for user in users}.values():
        try:
            with transaction.atomic():
                created.append(
                    Notification.objects.create(
                        user=user,
                        kind=kind,
                        title=title[:120],
                        body=body[:300],
                        route=route,
                        dedupe_key=dedupe_key,
                    )
                )
        except IntegrityError:
            continue  # a concurrent run told this person first
    if created:
        ids = [notification.pk for notification in created]

        def push():
            from .tasks import send_notifications

            send_notifications.delay(ids)

        transaction.on_commit(push)
    return created


def register_device(*, user, token, platform, app_version=""):
    """The phone's current token, for the account signed in on it."""
    device, _ = PushDevice.objects.update_or_create(
        token=token,
        defaults={"user": user, "platform": platform, "app_version": app_version},
    )
    return device


def unregister_device(*, user, token):
    """Signing out: this phone stops receiving this account's messages."""
    PushDevice.objects.filter(user=user, token=token).delete()


def mark_read(*, user, ids=None):
    pending = Notification.objects.filter(user=user, read_at__isnull=True)
    if ids is not None:
        pending = pending.filter(pk__in=ids)
    return pending.update(read_at=timezone.now())
