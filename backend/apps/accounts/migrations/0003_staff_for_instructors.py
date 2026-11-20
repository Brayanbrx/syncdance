from django.db import migrations
from django.db.models import Q


def staff_for_instructors(apps, schema_editor):
    """The role opens the Django Admin («Administrar cursos»): `User.save`
    sets `is_staff` for instructors and administrators, but accounts saved
    before that rule (or written without `save`, e.g. `update()`) kept
    `is_staff=False`. They signed in to the studio (JWT) and were refused by
    the Admin with the same password."""
    User = apps.get_model("accounts", "User")
    User.objects.filter(Q(role__in=("INSTRUCTOR", "ADMIN")) | Q(is_superuser=True)).filter(
        is_staff=False
    ).update(is_staff=True)


class Migration(migrations.Migration):
    dependencies = [("accounts", "0002_terms_acceptance")]

    operations = [migrations.RunPython(staff_for_instructors, migrations.RunPython.noop)]
