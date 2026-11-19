from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.seeds import ensure_superadmin

# What a fresh platform needs, in order. Every step is idempotent: it creates
# only what is missing and never undoes a change made afterwards, because the
# seed runs on every start of the backend (docker-compose*.yml). Add new steps
# here as functions that take `say` (print one line).
STEPS = (ensure_superadmin,)


class Command(BaseCommand):
    help = (
        "Semilla de la plataforma (desarrollo y producción): crea lo que falta para "
        "empezar, como el superadministrador de SEED_ADMIN_*. Corre en cada arranque."
    )

    @transaction.atomic
    def handle(self, *args, **options):
        for step in STEPS:
            step(self.stdout.write)
