from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import User

USERNAME = "admin"
PASSWORD = "admin"
EMAIL = "admin@syncdance.local"


class Command(BaseCommand):
    help = (
        "Semilla de desarrollo: superusuario admin / admin (rol Administrador). "
        "Crea la cuenta si falta; --reset-password devuelve la contraseña a admin. "
        "Se niega a correr con DEBUG desactivado."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--reset-password",
            action="store_true",
            help="Si la cuenta ya existe, vuelve a poner la contraseña de la semilla.",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        # A well-known password is only acceptable on a development server.
        if not settings.DEBUG:
            raise CommandError("seed_admin solo se ejecuta con DEBUG activo (desarrollo).")
        user = User.objects.filter(username=USERNAME).first()
        created = user is None
        if created:
            taken = User.objects.filter(email=EMAIL).exists()
            user = User(username=USERNAME, email="admin+seed@syncdance.local" if taken else EMAIL)
        user.role = User.Role.ADMIN
        user.is_staff = True
        user.is_superuser = True
        user.is_active = True
        if created or options["reset_password"]:
            # Seeds bypass the password validators on purpose (development only).
            user.set_password(PASSWORD)
        user.save()
        if created:
            self.stdout.write(self.style.SUCCESS("Semilla creada: admin / admin."))
        elif options["reset_password"]:
            self.stdout.write(self.style.SUCCESS("Semilla actualizada: contraseña admin."))
        else:
            self.stdout.write("= admin ya existe; usa --reset-password para volver a admin.")
