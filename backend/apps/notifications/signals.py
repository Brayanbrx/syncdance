"""Events with many entry points (Django Admin, panel, API) are caught when
the row is created. A notification problem never breaks the action itself."""

import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.coaching.models import Assignment, SessionNote
from apps.training.models import GameResult

from . import events

logger = logging.getLogger(__name__)


def on_create(handler):
    # No functools.wraps: Django inspects the receiver's own signature (with
    # DEBUG on) and must see **kwargs, not the wrapped handler's.
    def wrapper(sender, instance, created, raw=False, **kwargs):
        if not created or raw:
            return
        try:
            handler(instance)
        except Exception:
            logger.exception("notification not created", extra={"event": handler.__name__})

    wrapper.__name__ = handler.__name__
    return wrapper


@receiver(post_save, sender=Assignment, dispatch_uid="notify_assignment_created")
@on_create
def assignment_created(instance):
    events.assignment_created(instance)


@receiver(post_save, sender=SessionNote, dispatch_uid="notify_session_note_created")
@on_create
def session_note_created(instance):
    events.session_note_created(instance)


@receiver(post_save, sender=GameResult, dispatch_uid="notify_game_saved")
@on_create
def game_saved(instance):
    events.game_saved(instance)


def safely(event, *args):
    """For explicit calls from services and tasks."""
    try:
        event(*args)
    except Exception:
        logger.exception("notification not created", extra={"event": event.__name__})
