from django.core.management.base import BaseCommand, CommandError

from apps.routines.standard import install


class Command(BaseCommand):
    help = (
        "Genera el estándar SyncDance: video del coach con su ritmo y referencia "
        "exacta desde cada coreografía. Crea solo las rutinas que falten."
    )

    def add_arguments(self, parser):
        parser.add_argument("--only", nargs="*", help="Claves concretas (p. ej. n1-marcha).")

    def handle(self, *args, **options):
        try:
            created = install(only=options["only"], log=self.stdout.write)
        except (ImportError, OSError) as exc:
            raise CommandError(
                "No se pudo renderizar: ejecuta el comando en la imagen del backend "
                f"con las dependencias de pose ({exc})."
            ) from exc
        self.stdout.write(self.style.SUCCESS(f"Rutinas nuevas: {created}."))
