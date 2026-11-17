"""What an instructor sees of a course: where its students struggle.

Difficulty map (`difficulty-map-v1`): for each step the instructor published,
each student's latest comparable result and, for the group, the median, the
share under the threshold and the sample size. Comparable means the version
students download now, one follow mode and one speed: results are never
mixed across them. A step without evidence is None ("—"), never 0, and group
figures need at least MIN_GROUP students.
"""

from collections import Counter, defaultdict
from statistics import median

from django.db.models import Prefetch, Q

from apps.coaching.models import Enrollment, PracticeRating
from apps.coaching.serializers import display_name
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession, FeedbackCount, StepResult

MAP_VERSION = "difficulty-map-v1"
MIN_GROUP = 3
THRESHOLD = 50.0  # GOOD in the dance game; provisional until physical validation
MIN_COVERAGE = 0.5  # same provisional floor as routine progress
TOP_ERRORS = 3
RECENT_PRACTICES = 50


def course_routines(course):
    """Routines the course works on: published in it or assigned to it."""
    return (
        Routine.objects.filter(Q(published_in_courses=course) | Q(assignments__course=course))
        .distinct()
        .order_by("name", "pk")
    )


def _ready_references():
    return RoutineReference.objects.filter(status=RoutineReference.Status.READY).exclude(
        reference_asset=""
    )


def published_reference(routine):
    """The version students download now (as `GET /routines/{id}/reference/`)."""
    ready = getattr(routine, "ready_references", None)
    if ready is not None:  # loaded by course_routine_options, newest first
        master = routine.master_video.name or ""
        return next((r for r in ready if (r.source_video.name or "") == master), None)
    current = _ready_references().filter(routine=routine, source_video=routine.master_video.name)
    return current.first()


def course_routine_options(course):
    """The course's routines with their ready versions: two queries, however
    many routines the course has."""
    return course_routines(course).prefetch_related(
        Prefetch("references", queryset=_ready_references(), to_attr="ready_references")
    )


def _steps_of(reference):
    profile = (reference.scoring_profile or {}) if reference else {}
    return (profile.get("steps") or {}).get("items") or []


def step_map(*, course, routine, follow_mode, speed):
    reference = published_reference(routine)
    steps = _steps_of(reference)
    enrollments = list(
        Enrollment.objects.filter(course=course)
        .select_related("student")
        .order_by("student__username")
    )
    ids = [e.student_id for e in enrollments]
    results = []
    if steps:
        results = (
            StepResult.objects.filter(
                session__reference=reference,
                session__student_id__in=ids,
                session__follow_mode=follow_mode,
                session__playback_speed=speed,
                session__status=DanceSession.Status.COMPLETED,
            )
            .select_related("session")
            .order_by("-session__started_at", "index")
        )
    latest = {}  # (student, step) -> score of the newest practice with evidence
    practices = defaultdict(set)
    last_practice = {}
    errors = defaultdict(lambda: defaultdict(set))  # step -> code -> students
    shown = defaultdict(Counter)  # step -> code -> times shown
    for result in results:
        student = result.session.student_id
        practices[student].add(result.session_id)
        last_practice.setdefault(student, result.session.started_at)
        if result.score is not None and result.coverage >= MIN_COVERAGE:
            latest.setdefault((student, result.index), result.score)
        for code, count in result.feedback.items():
            errors[result.index][code].add(student)
            shown[result.index][code] += count
    messages = {
        code: (message, region)
        for code, message, region in FeedbackCount.objects.filter(
            session_id__in={s for group in practices.values() for s in group}
        ).values_list("code", "message", "region")
    }
    practiced = len(practices)
    summaries = []
    for index, step in enumerate(steps):
        values = [latest[(s, index)] for s in ids if (s, index) in latest]
        group = len(values) >= MIN_GROUP
        frequent = sorted(
            errors[index].items(), key=lambda item: (-len(item[1]), -shown[index][item[0]])
        )[:TOP_ERRORS]
        summaries.append(
            {
                "index": index,
                "name": step["name"],
                "counts": step["counts"],
                "start_ms": step["start_ms"],
                "end_ms": step["end_ms"],
                "students": len(values),
                "median": round(median(values), 1) if group else None,
                "below_threshold": sum(v < THRESHOLD for v in values) / len(values)
                if group
                else None,
                "frequent_errors": [
                    {
                        "code": code,
                        "message": messages.get(code, (code, ""))[0],
                        "region": messages.get(code, ("", ""))[1],
                        "students": len(students),
                        "count": shown[index][code],
                    }
                    for code, students in frequent
                ]
                if practiced >= MIN_GROUP
                else [],
            }
        )
    return {
        "version": MAP_VERSION,
        "routine": {"id": routine.pk, "name": routine.name},
        "reference_version": reference.version if reference else None,
        "follow_mode": follow_mode,
        "speed": speed,
        "min_group": MIN_GROUP,
        "threshold": THRESHOLD,
        "steps": summaries,
        "students": [
            {
                "id": e.student_id,
                "name": display_name(e.student),
                "practices": len(practices[e.student_id]),
                "last_practice_at": last_practice.get(e.student_id),
                "scores": [latest.get((e.student_id, i)) for i in range(len(steps))],
            }
            for e in enrollments
        ],
    }


def recent_practices(*, course, instructor, limit=RECENT_PRACTICES):
    """The course's latest practices, with this instructor's rating of each."""
    return (
        DanceSession.objects.filter(
            student__enrollments__course=course, status=DanceSession.Status.COMPLETED
        )
        .select_related("student", "routine", "game")
        .prefetch_related(
            Prefetch(
                "ratings",
                queryset=PracticeRating.objects.filter(instructor=instructor),
                to_attr="my_ratings",
            )
        )
        .distinct()
        .order_by("-started_at")[:limit]
    )
