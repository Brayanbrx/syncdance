import logging
from collections import defaultdict

from celery import shared_task
from django.utils import timezone

from . import events, fcm
from .models import Notification, PushDevice

logger = logging.getLogger(__name__)


@shared_task(ignore_result=True)
def send_notifications(notification_ids):
    """Push saved notifications to their owners' phones. A failure never
    loses the notification: it stays in the inbox."""
    notifications = Notification.objects.filter(
        pk__in=notification_ids, pushed_at__isnull=True
    ).select_related("user")
    tokens = defaultdict(list)
    for device in PushDevice.objects.filter(
        user_id__in={notification.user_id for notification in notifications}
    ):
        tokens[device.user_id].append(device.token)
    for notification in notifications:
        user_tokens = tokens.get(notification.user_id)
        if not user_tokens:
            continue
        try:
            result = fcm.send(
                user_tokens,
                title=notification.title,
                body=notification.body,
                data={
                    "notification_id": str(notification.pk),
                    "kind": notification.kind,
                    "route": notification.route,
                },
            )
        except Exception:
            logger.exception("push failed", extra={"notification_id": notification.pk})
            continue
        if result.stale_tokens:
            PushDevice.objects.filter(token__in=result.stale_tokens).delete()
        if result.sent:
            Notification.objects.filter(pk=notification.pk).update(pushed_at=timezone.now())


@shared_task(ignore_result=True)
def remind_due_assignments():
    """Periodic (Celery Beat): the day before a due date, students who have
    not met the goal yet are reminded once."""
    reminded = events.assignments_due_tomorrow()
    if reminded:
        logger.info("due reminders sent", extra={"count": reminded})
