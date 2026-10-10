from django.db import transaction

from .models import Routine
from .reference_services import queue_reference


@transaction.atomic
def create_routine(*, instructor, **validated_data) -> Routine:
    routine = Routine.objects.create(instructor=instructor, **validated_data)
    if routine.master_video:
        queue_reference(routine_id=routine.pk)
    return routine


@transaction.atomic
def update_routine(*, routine: Routine, **validated_data) -> Routine:
    previous_video = routine.master_video.name
    for field, value in validated_data.items():
        setattr(routine, field, value)
    routine.save()
    if routine.master_video.name != previous_video:
        routine.duration_ms = 0
        routine.save(update_fields=["duration_ms"])
        if routine.master_video:
            queue_reference(routine_id=routine.pk)
    return routine
