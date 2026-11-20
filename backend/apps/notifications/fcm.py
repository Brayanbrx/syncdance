"""Firebase Cloud Messaging, behind one function.

Without credentials (development, tests) nothing is sent and the inbox still
works. FIREBASE_CREDENTIALS is the path of the service-account JSON
downloaded from Firebase (Project settings → Service accounts); it is a
secret and never goes into the repository.
"""

import logging
import os
from dataclasses import dataclass

logger = logging.getLogger(__name__)

_app = None


@dataclass(frozen=True)
class PushResult:
    sent: int
    # Tokens FCM says no longer exist (app uninstalled, data cleared).
    stale_tokens: tuple[str, ...]


def credentials_path() -> str:
    return os.getenv("FIREBASE_CREDENTIALS", "").strip()


def is_configured() -> bool:
    path = credentials_path()
    return bool(path) and os.path.isfile(path)


def _firebase_app():
    global _app
    if _app is None:
        import firebase_admin
        from firebase_admin import credentials

        _app = firebase_admin.initialize_app(credentials.Certificate(credentials_path()))
    return _app


def send(tokens, *, title, body, data) -> PushResult:
    """One message to several phones. `data` values must be strings."""
    tokens = list(tokens)
    if not tokens:
        return PushResult(0, ())
    if not is_configured():
        logger.info("push skipped: FIREBASE_CREDENTIALS not configured")
        return PushResult(0, ())
    from firebase_admin import exceptions, messaging

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=data,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(channel_id="syncdance_general"),
        ),
    )
    response = messaging.send_each_for_multicast(message, app=_firebase_app())
    stale = []
    for token, result in zip(tokens, response.responses, strict=True):
        if result.success:
            continue
        error = result.exception
        gone = (
            messaging.UnregisteredError,
            messaging.SenderIdMismatchError,
            exceptions.InvalidArgumentError,
        )
        if isinstance(error, gone):
            stale.append(token)
        else:
            logger.warning("push failed", extra={"error": str(error)})
    return PushResult(response.success_count, tuple(stale))
