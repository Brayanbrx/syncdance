from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

score_validators = [MinValueValidator(0), MaxValueValidator(100)]


class Analysis(models.Model):
    performance = models.OneToOneField(
        "performances.Performance",
        on_delete=models.CASCADE,
        related_name="analysis",
    )
    dance_score = models.DecimalField(max_digits=5, decimal_places=2, validators=score_validators)
    # Compatibility field for legacy clients. Voice is not required for dance.
    voice_score = models.DecimalField(
        max_digits=5, decimal_places=2, validators=score_validators, null=True, blank=True
    )
    rhythm_score = models.DecimalField(max_digits=5, decimal_places=2, validators=score_validators)
    sync_score = models.DecimalField(max_digits=5, decimal_places=2, validators=score_validators)
    overall_score = models.DecimalField(max_digits=5, decimal_places=2, validators=score_validators)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Analysis #{self.pk}"
