import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from apps.accounts.models import User
from apps.routines.models import Routine, RoutineReference


@pytest.mark.django_db
def test_ready_reference_requires_artifact_and_provenance():
    teacher = User.objects.create_user(username="teacher", email="t@example.com")
    routine = Routine.objects.create(name="Demo", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference(routine=routine, version=1, status="READY")
    with pytest.raises(ValidationError):
        reference.full_clean()
    reference.reference_asset = "references/demo.json.gz"
    reference.engine_name = "fixture"
    reference.algorithm_version = "fixture-v1"
    reference.duration_ms = 1000
    reference.checksum_sha256 = "a" * 64
    reference.full_clean()
    reference.save()
    with transaction.atomic(), pytest.raises(IntegrityError):
        RoutineReference.objects.create(routine=routine, version=1)
