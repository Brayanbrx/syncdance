import pytest

from apps.accounts.models import User
from apps.performances.models import Performance
from apps.performances.tasks import analyze_performance
from apps.routines.models import Routine


@pytest.mark.django_db
def test_legacy_celery_task_remains_dance_only():
    user = User.objects.create_user(username="demo", email="demo@example.com")
    routine = Routine.objects.create(name="Demo", instructor=user, difficulty="BEGINNER")
    performance = Performance.objects.create(student=user, routine=routine)
    # Eager execution verifies the task without a running broker.
    analyze_performance.apply(args=[performance.pk], throw=True)
    performance.refresh_from_db()
    assert performance.status == "COMPLETED"
    assert performance.analysis.voice_score is None
    assert performance.analysis.overall_score == 83
