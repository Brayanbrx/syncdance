"""Mail through Brevo's transactional API over HTTPS (MAIL_PROVIDER=brevo).

No SMTP port or password: one POST per message with the account's API key.
Network failures and Brevo's own outages (5xx, 429) raise OSError, so the
Celery task that sends the mail retries them; a refusal (bad key, unverified
sender) raises MailRejected, which retrying would not fix.
"""

import json
import logging
import urllib.error
import urllib.request
from email.utils import getaddresses, parseaddr

from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

logger = logging.getLogger(__name__)

BREVO_URL = "https://api.brevo.com/v3/smtp/email"


class MailRejected(Exception):
    """Brevo refused the message: the key, the sender or the content is wrong."""


def _contact(address: str) -> dict:
    name, email = parseaddr(address)
    return {"email": email, "name": name} if name else {"email": email}


def _contacts(addresses) -> list[dict]:
    return [
        {"email": email, "name": name} if name else {"email": email}
        for name, email in getaddresses(addresses)
    ]


def _refusal(error: urllib.error.HTTPError) -> str:
    """Brevo answers {"code": ..., "message": ...}; never echo the request."""
    try:
        body = json.loads(error.read() or b"{}")
    except (ValueError, OSError):
        body = {}
    return f"{body.get('code', error.reason)}: {body.get('message', '')}".strip(": ")


class BrevoEmailBackend(BaseEmailBackend):
    def __init__(self, fail_silently=False, api_key=None, timeout=None, **kwargs):
        super().__init__(fail_silently=fail_silently, **kwargs)
        self.api_key = api_key or settings.BREVO_API_KEY
        self.timeout = timeout or settings.EMAIL_TIMEOUT

    def send_messages(self, email_messages):
        sent = 0
        for message in email_messages:
            if not message.recipients():
                continue
            try:
                self._send(message)
            except Exception:
                if not self.fail_silently:
                    raise
            else:
                sent += 1
        return sent

    @staticmethod
    def payload(message) -> dict:
        if message.attachments:
            raise MailRejected("El envío por Brevo no admite adjuntos todavía.")
        data = {
            "sender": _contact(message.from_email),
            "to": _contacts(message.to),
            "subject": message.subject,
        }
        if message.cc:
            data["cc"] = _contacts(message.cc)
        if message.bcc:
            data["bcc"] = _contacts(message.bcc)
        if message.reply_to:
            data["replyTo"] = _contact(message.reply_to[0])
        if message.content_subtype == "html":
            data["htmlContent"] = message.body
        else:
            data["textContent"] = message.body
            for content, mimetype in getattr(message, "alternatives", []):
                if mimetype == "text/html":
                    data["htmlContent"] = content
        return data

    def _send(self, message) -> None:
        request = urllib.request.Request(
            BREVO_URL,
            data=json.dumps(self.payload(message)).encode(),
            headers={
                "api-key": self.api_key,
                "accept": "application/json",
                "content-type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                answer = json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            if error.code >= 500 or error.code == 429:
                raise  # an OSError: the task tries again later
            raise MailRejected(
                f"Brevo rechazó el correo ({error.code}): {_refusal(error)}"
            ) from None
        logger.info("mail sent", extra={"provider": "brevo", "message_id": answer.get("messageId")})
