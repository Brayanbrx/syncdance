from smtplib import SMTPException

from celery import shared_task

from .models import User
from .services import send_password_reset_email


@shared_task(
    ignore_result=True,
    autoretry_for=(OSError, SMTPException),
    retry_backoff=30,
    max_retries=4,
)
def send_password_reset(user_id: int) -> None:
    """The link is built here, at send time: a retry still sends a valid one."""
    user = User.objects.filter(pk=user_id, is_active=True).first()
    if user is not None:
        send_password_reset_email(user)
