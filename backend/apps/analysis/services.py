from decimal import Decimal

from apps.performances.models import Performance

from .models import Analysis


def complete_analysis(*, performance: Performance) -> Analysis:
    result, _ = Analysis.objects.update_or_create(
        performance=performance,
        defaults={
            "dance_score": Decimal("85.00"),
            "voice_score": None,
            "rhythm_score": Decimal("84.00"),
            "sync_score": Decimal("80.00"),
            "overall_score": Decimal("83.00"),
        },
    )
    performance.status = Performance.Status.COMPLETED
    performance.save(update_fields=("status", "updated_at"))
    return result
