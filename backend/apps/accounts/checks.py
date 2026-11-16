from django.conf import settings
from django.core.checks import Tags, Warning, register


@register(Tags.security, deploy=True)
def legal_contact(app_configs, **kwargs):
    """The privacy policy must say whom to write to (Google Play asks too)."""
    if settings.LEGAL_CONTACT_EMAIL:
        return []
    return [
        Warning(
            "LEGAL_CONTACT_EMAIL está vacío: la política de privacidad no muestra a quién "
            "escribir.",
            hint="Definir LEGAL_CONTROLLER y LEGAL_CONTACT_EMAIL en .env.prod.",
            id="accounts.W001",
        )
    ]
