from django.core.management.base import BaseCommand, CommandError

from ai_engine.voice import VoiceError
from apps.routines.singing import install


class Command(BaseCommand):
    help = (
        "Genera los ejercicios de canto de SyncDance: audio guía con cuenta de "
        "entrada y referencia exacta desde sus notas. Crea solo los que falten."
    )

    def add_arguments(self, parser):
        parser.add_argument("--only", nargs="*", help="Claves concretas (p. ej. v1-arpegio).")
        parser.add_argument(
            "--refresh",
            action="store_true",
            help="Regenera los instalados y publica una versión nueva si el resultado cambió.",
        )

    def handle(self, *args, **options):
        try:
            changed = install(
                only=options["only"], refresh=options["refresh"], log=self.stdout.write
            )
        except (ImportError, OSError, VoiceError) as exc:
            raise CommandError(
                "No se pudo generar el audio: ejecuta el comando en la imagen del backend "
                f"con las dependencias de voz ({exc})."
            ) from exc
        self.stdout.write(self.style.SUCCESS(f"Ejercicios nuevos o actualizados: {changed}."))
