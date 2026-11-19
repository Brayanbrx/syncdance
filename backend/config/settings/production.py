import os

from django.core.exceptions import ImproperlyConfigured

from .base import *  # noqa: F403
from .base import MAIL_BACKENDS, MAIL_PROVIDER, MIDDLEWARE, SECRET_KEY, env_list

DEBUG = False

# A missing or sample key would sign every token with a public value.
if not os.getenv("DJANGO_SECRET_KEY") or SECRET_KEY.startswith(("unsafe-", "change-me")):
    raise ImproperlyConfigured("DJANGO_SECRET_KEY debe ser un valor largo y aleatorio.")

# gunicorn has no static server: WhiteNoise serves the admin's files with
# hashed names, compressed, from the collectstatic of the image build.
MIDDLEWARE = list(MIDDLEWARE)
MIDDLEWARE.insert(
    MIDDLEWARE.index("django.middleware.security.SecurityMiddleware") + 1,
    "whitenoise.middleware.WhiteNoiseMiddleware",
)
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

# HTTPS ends at the proxy (Caddy), which forwards the original scheme.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = os.getenv("DJANGO_SECURE_SSL_REDIRECT", "true").lower() == "true"
# The container health check calls Django directly over plain HTTP.
SECURE_REDIRECT_EXEMPT = [r"^api/health/$"]
# Start short: once the domain is final, raise it (e.g. 31536000).
SECURE_HSTS_SECONDS = int(os.getenv("DJANGO_SECURE_HSTS_SECONDS", "86400"))
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
# Django Admin forms over HTTPS: e.g. https://syncdance.example
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

EMAIL_BACKEND = MAIL_BACKENDS.get(MAIL_PROVIDER) or os.getenv(
    "DJANGO_EMAIL_BACKEND", "django.core.mail.backends.smtp.EmailBackend"
)
PUBLIC_WEB_URL = os.getenv(
    "PUBLIC_WEB_URL", f"https://{os.getenv('SYNCDANCE_DOMAIN', 'localhost')}"
).rstrip("/")

# Subdomains and the browsers' preload list commit the whole domain to HTTPS
# for months; decide them when the final domain exists.
SILENCED_SYSTEM_CHECKS = ["security.W005", "security.W021"]
