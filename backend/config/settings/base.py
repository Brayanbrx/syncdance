import os
from datetime import timedelta
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def env_list(name: str, default: str = "") -> list[str]:
    return [value.strip() for value in os.getenv(name, default).split(",") if value.strip()]


SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-development-secret-key-change-me")
DEBUG = False
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,backend")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    "rest_framework_simplejwt.token_blacklist",
    "drf_spectacular",
    # Modulos internos
    "apps.accounts",
    "apps.routines",
    "apps.training",
    "apps.performances",
    "apps.analysis",
    "apps.coaching",
    "apps.backoffice",
    "apps.studio",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

# Django Admin is the administration UI during the mobile MVP.
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("POSTGRES_DB", "syncdance"),
        "USER": os.getenv("POSTGRES_USER", "syncdance"),
        "PASSWORD": os.getenv("POSTGRES_PASSWORD", "syncdance"),
        "HOST": os.getenv("POSTGRES_HOST", "postgres"),
        "PORT": os.getenv("POSTGRES_PORT", "5432"),
    }
}

# Validaciones para Contraseñas
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "es"
TIME_ZONE = "America/La_Paz"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "accounts.User"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    # Login per account name, sign-up per address, reset links per mailbox (see
    # accounts.views) and course codes per account, so codes cannot be guessed
    # (coaching.views).
    "DEFAULT_THROTTLE_RATES": {
        "login": "10/minute",
        "register": "100/hour",
        "password_reset": "5/hour",
        "password_reset_confirm": "30/hour",
        "account_delete": "10/hour",
        "join": "20/hour",
        # Error reports of the Android app, per address: a crash loop on
        # one phone cannot flood the table (repeats are only counted anyway).
        "app_errors": "60/hour",
    },
}

# Public address of the web (landing and account pages): reset links point
# to it. Production derives it from SYNCDANCE_DOMAIN.
PUBLIC_WEB_URL = os.getenv("PUBLIC_WEB_URL", "http://localhost:8085").rstrip("/")
PASSWORD_RESET_TIMEOUT = 2 * 60 * 60

# Privacy policy and terms (web pages /privacidad and /terminos). Who is
# responsible for the data and whom to write to come from the environment.
# Changing those texts in frontend/src/app/features/legal means a new version
# here: sign-up stores the version each person accepted.
LEGAL_CONTROLLER = os.getenv("LEGAL_CONTROLLER", "el equipo de SyncDance")
LEGAL_CONTACT_EMAIL = os.getenv("LEGAL_CONTACT_EMAIL", "")
LEGAL_TERMS_VERSION = "2026-11-17"

# How mail leaves. MAIL_PROVIDER chooses: "brevo" (Brevo's HTTPS API with
# BREVO_API_KEY, common/mail.py), "smtp" (the EMAIL_* below) or "console" (the
# backend log). Unset, DJANGO_EMAIL_BACKEND decides: the log in development,
# SMTP in production (production.py).
MAIL_BACKENDS = {
    "brevo": "common.mail.BrevoEmailBackend",
    "smtp": "django.core.mail.backends.smtp.EmailBackend",
    "console": "django.core.mail.backends.console.EmailBackend",
}
MAIL_PROVIDER = os.getenv("MAIL_PROVIDER", "").strip().lower()
if MAIL_PROVIDER and MAIL_PROVIDER not in MAIL_BACKENDS:
    raise ImproperlyConfigured(
        f"MAIL_PROVIDER={MAIL_PROVIDER} no existe: usa {', '.join(MAIL_BACKENDS)} o déjalo vacío."
    )
BREVO_API_KEY = os.getenv("BREVO_API_KEY", "").strip()
MAIL_FROM = os.getenv("MAIL_FROM", "").strip()
MAIL_FROM_NAME = os.getenv("MAIL_FROM_NAME", "SyncDance").strip()
if MAIL_PROVIDER == "brevo" and not (BREVO_API_KEY and MAIL_FROM):
    raise ImproperlyConfigured(
        "MAIL_PROVIDER=brevo necesita BREVO_API_KEY y MAIL_FROM (un remitente verificado en Brevo)."
    )
EMAIL_BACKEND = MAIL_BACKENDS.get(MAIL_PROVIDER) or os.getenv(
    "DJANGO_EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend"
)
EMAIL_HOST = os.getenv("EMAIL_HOST", "localhost")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = os.getenv("EMAIL_USE_TLS", "true").lower() == "true"
EMAIL_TIMEOUT = 10
if MAIL_FROM:
    # Quoted, so a name with commas or accents stays one display name.
    _name = MAIL_FROM_NAME.replace("\\", "\\\\").replace('"', '\\"')
    DEFAULT_FROM_EMAIL = f'"{_name}" <{MAIL_FROM}>' if _name else MAIL_FROM
else:
    DEFAULT_FROM_EMAIL = os.getenv("DEFAULT_FROM_EMAIL", "SyncDance <no-responder@localhost>")

# The phone keeps only the refresh token (secure storage) to reopen offline and
# renew later. Rotation + blacklist invalidate a refresh token once it is used.
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
}

SPECTACULAR_SETTINGS = {
    "TITLE": "SyncDance AI API",
    "DESCRIPTION": (
        "Entrenamiento móvil live-first: catálogo, referencias versionadas y sesiones. "
        "Pose y scoring se ejecutan en el dispositivo. Performances es el flujo offline heredado."
    ),
    "VERSION": "0.2.0",
    "ENUM_NAME_OVERRIDES": {
        "BodySegmentEnum": "apps.training.models.SegmentScore.Segment",
    },
}

CORS_ALLOWED_ORIGINS = env_list("CORS_ALLOWED_ORIGINS", "http://localhost:4200")
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0")
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", "redis://redis:6379/1")
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60
# Run a single Beat process (see docker-compose `celery-beat`).
CELERY_BEAT_SCHEDULE = {
    "expire-stale-references": {
        "task": "apps.routines.tasks.expire_stale_references",
        "schedule": timedelta(minutes=10),
        "options": {"expires": 9 * 60},
    },
}
# The worker logs through LOGGING below instead of replacing the root handlers.
CELERY_WORKER_HIJACK_ROOT_LOGGER = False

# Structured logs on stdout (Docker): one JSON object per line with ids such
# as reference_id, task_id or session_id. DJANGO_LOG_FORMAT=text reads easier
# in a local terminal.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "common.logging.JsonFormatter"},
        "text": {"format": "%(asctime)s %(levelname)s %(name)s: %(message)s"},
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "text" if os.getenv("DJANGO_LOG_FORMAT") == "text" else "json",
        },
    },
    "root": {"handlers": ["console"], "level": os.getenv("DJANGO_LOG_LEVEL", "INFO")},
    # Replace Django's default handlers so its lines are not printed twice.
    # Request lines stay: they show whether the phone reaches the server.
    "loggers": {
        "django": {"handlers": ["console"], "level": "INFO", "propagate": False},
        "django.server": {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}

POSE_MODEL_PATH = os.getenv(
    "POSE_MODEL_PATH", str(BASE_DIR / "models" / "pose_landmarker_lite.task")
)
