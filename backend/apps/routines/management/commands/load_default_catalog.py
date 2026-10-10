from django.core.management.base import BaseCommand, CommandError

from apps.routines.catalog import MANIFEST, CatalogError, install, load_manifest


class Command(BaseCommand):
    help = (
        "Descarga desde su origen los videos del catálogo por defecto (licencia "
        "libre, SHA-256 fijado), crea las rutinas que falten y encola sus referencias."
    )

    def add_arguments(self, parser):
        parser.add_argument("--manifest", default=str(MANIFEST))
        parser.add_argument("--only", nargs="*", help="Claves concretas a instalar.")

    def handle(self, *args, **options):
        try:
            entries = load_manifest(options["manifest"])
            created = install(entries, only=options["only"], log=self.stdout.write)
        except (CatalogError, OSError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(self.style.SUCCESS(f"Rutinas nuevas: {created}."))
