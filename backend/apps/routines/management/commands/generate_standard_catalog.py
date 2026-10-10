from django.core.management.base import BaseCommand, CommandError

from apps.routines.standard import install


class Command(BaseCommand):
    help = (
        "Genera el estándar SyncDance: video del coach con su ritmo y referencia "
        "exacta desde cada coreografía. Crea solo las rutinas que falten."
    )

    def add_arguments(self, parser):
        parser.add_argument("--only", nargs="*", help="Claves concretas (p. ej. n1-marcha).")
        parser.add_argument(
            "--refresh",
            action="store_true",
            help="Regenera las instaladas y publica una versión nueva si el resultado cambió.",
        )

    def handle(self, *args, **options):
        try:
            changed = install(
                only=options["only"], refresh=options["refresh"], log=self.stdout.write
            )
        except (ImportError, OSError) as exc:
            raise CommandError(
                "No se pudo renderizar: ejecuta el comando en la imagen del backend "
                f"con las dependencias de pose ({exc})."
            ) from exc
        self.stdout.write(self.style.SUCCESS(f"Rutinas nuevas o actualizadas: {changed}."))
