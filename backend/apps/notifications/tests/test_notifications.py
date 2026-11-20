from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.backoffice.models import AppRelease
from apps.backoffice.services import report_app_error, update_release
from apps.coaching.models import Assignment, Course, Enrollment, SessionNote
from apps.notifications import events, fcm, tasks
from apps.notifications.fcm import PushResult
from apps.notifications.models import Notification, PushDevice
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession, GameResult

pytestmark = pytest.mark.django_db


@pytest.fixture
def sent(monkeypatch):
    """Messages that would reach FCM; the token "stale" no longer exists."""
    messages = []

    def fake_send(tokens, *, title, body, data):
        tokens = list(tokens)
        messages.append({"tokens": tokens, "title": title, "body": body, "data": data})
        stale = tuple(token for token in tokens if token == "stale")
        return PushResult(len(tokens) - len(stale), stale)

    monkeypatch.setattr(fcm, "send", fake_send)
    return messages


@pytest.fixture
def world(db, django_capture_on_commit_callbacks):
    teacher = User.objects.create_user(
        username="profe", email="p@example.com", password="x", role="INSTRUCTOR"
    )
    ana = User.objects.create_user(username="ana", email="a@example.com", password="x")
    luis = User.objects.create_user(username="luis", email="l@example.com", password="x")
    admin = User.objects.create_user(
        username="jefa", email="j@example.com", password="x", role="ADMIN"
    )
    routine = Routine.objects.create(name="Paso básico", instructor=teacher, difficulty="BEGINNER")
    reference = RoutineReference.objects.create(
        routine=routine,
        version=1,
        status="READY",
        reference_asset="references/demo.json.gz",
        engine_name="fixture",
        checksum_sha256="a" * 64,
        algorithm_version="fixture-v1",
        duration_ms=10000,
    )
    course = Course.objects.create(name="Danza 1A", instructor=teacher, join_code="ABCD2345")
    Enrollment.objects.create(course=course, student=ana)
    Enrollment.objects.create(course=course, student=luis)
    return {
        "teacher": teacher,
        "ana": ana,
        "luis": luis,
        "admin": admin,
        "routine": routine,
        "reference": reference,
        "course": course,
    }


def assign(world, capture, **fields):
    with capture(execute=True):
        return Assignment.objects.create(
            course=world["course"], routine=world["routine"], target_stars=3, **fields
        )


def game(world, student, *, points, speed=1.0):
    now = timezone.now()
    session = DanceSession.objects.create(
        student=student,
        routine=world["routine"],
        reference=world["reference"],
        started_at=now,
        finished_at=now,
        status="COMPLETED",
        playback_speed=speed,
        reference_version=1,
    )
    GameResult.objects.create(
        session=session,
        version="dance-game-v2",
        points=points,
        max_points=400,
        max_combo=1,
        perfect=points // 100,
        great=0,
        good=0,
        miss=4 - points // 100,
        unrated=0,
    )
    return session


def titles(user):
    return [n.title for n in Notification.objects.filter(user=user)]


def test_a_new_assignment_reaches_every_student_of_the_course_once(
    world, sent, django_capture_on_commit_callbacks
):
    PushDevice.objects.create(user=world["ana"], token="ana-phone")
    assignment = assign(
        world,
        django_capture_on_commit_callbacks,
        due_date=timezone.localdate() + timedelta(days=5),
    )
    assert titles(world["ana"]) == ["Nueva tarea en Danza 1A"]
    assert titles(world["luis"]) == ["Nueva tarea en Danza 1A"]
    assert titles(world["teacher"]) == []
    note = Notification.objects.get(user=world["ana"])
    assert "Paso básico: meta ★★★ · vence el" in note.body
    assert note.route == "/courses"
    # Only Ana has a phone: one push, and it is marked as sent.
    assert [m["tokens"] for m in sent] == [["ana-phone"]]
    assert sent[0]["data"]["route"] == "/courses"
    note.refresh_from_db()
    assert note.pushed_at is not None
    # Saving the assignment again (an edit) does not repeat the message.
    assignment.instructions = "Con espejo"
    assignment.save()
    events.assignment_created(assignment)
    assert Notification.objects.filter(kind="ASSIGNMENT_NEW").count() == 2


def test_tokens_fcm_no_longer_knows_are_forgotten(world, sent, django_capture_on_commit_callbacks):
    PushDevice.objects.create(user=world["ana"], token="stale")
    PushDevice.objects.create(user=world["ana"], token="new-phone")
    assign(world, django_capture_on_commit_callbacks)
    assert list(PushDevice.objects.values_list("token", flat=True)) == ["new-phone"]


def test_the_day_before_the_due_date_only_pending_students_are_reminded(
    world, sent, django_capture_on_commit_callbacks
):
    tomorrow = timezone.localdate() + timedelta(days=1)
    assign(world, django_capture_on_commit_callbacks, due_date=tomorrow)
    game(world, world["luis"], points=400)  # Luis already met the goal
    tasks.remind_due_assignments()
    tasks.remind_due_assignments()  # hourly runs never repeat it
    assert Notification.objects.filter(kind="ASSIGNMENT_DUE").count() == 1
    assert "Mañana vence una tarea" in titles(world["ana"])


def test_meeting_a_goal_tells_the_instructor_the_first_time(
    world, sent, django_capture_on_commit_callbacks
):
    assign(world, django_capture_on_commit_callbacks)
    game(world, world["ana"], points=100)  # below the goal
    game(world, world["ana"], points=400, speed=0.5)  # slower: never counts
    assert titles(world["teacher"]) == []
    game(world, world["ana"], points=400)
    game(world, world["ana"], points=400)
    assert titles(world["teacher"]) == ["ana cumplió una tarea"]


def test_an_instructor_note_reaches_the_student(world, sent):
    session = game(world, world["ana"], points=100)
    SessionNote.objects.create(session=session, author=world["teacher"], text="Sube los brazos")
    note = Notification.objects.get(user=world["ana"], kind="SESSION_NOTE")
    assert note.title == "profe comentó tu práctica"
    assert note.body == "Paso básico: Sube los brazos"


def test_a_routine_in_the_catalog_reaches_students_but_not_its_author(world, sent):
    events.routine_entered_catalog(world["routine"])
    events.routine_entered_catalog(world["routine"])
    assert Notification.objects.filter(kind="CATALOG_NEW").count() == 2
    assert titles(world["teacher"]) == []
    assert Notification.objects.get(user=world["ana"]).route == "/routines"


def test_installed_catalogs_never_notify_their_uploader(world, sent):
    reference = world["reference"]
    events.reference_finished(reference)
    assert titles(world["teacher"]) == ["«Paso básico» está lista para publicar"]
    Routine.objects.filter(pk=world["routine"].pk).update(catalog_key="demo")
    reference.refresh_from_db()
    reference.pk = None  # a second version of an installed routine
    events.reference_finished(reference)
    assert Notification.objects.count() == 1


def test_publishing_a_release_tells_the_phones(world, sent):
    PushDevice.objects.create(user=world["ana"], token="ana-phone")
    release = AppRelease.objects.create(version_name="1.2.0", version_code=12, apk="x.apk")
    update_release(release=release, notes="Más rápida")
    assert Notification.objects.count() == 0
    update_release(release=release, is_published=True)
    assert titles(world["ana"]) == ["Hay una versión nueva de SyncDance"]
    assert titles(world["luis"]) == []  # no phone registered


def test_only_the_first_occurrence_of_an_app_error_tells_the_admins(world, sent):
    report_app_error(app_version="1.0.0", kind="FlutterError", message="boom", stack="a\nb")
    report_app_error(app_version="1.0.0", kind="FlutterError", message="boom", stack="a\nb")
    assert titles(world["admin"]) == ["Error nuevo en la app 1.0.0"]
    assert titles(world["ana"]) == []


def test_without_firebase_credentials_nothing_is_sent(world, monkeypatch):
    monkeypatch.delenv("FIREBASE_CREDENTIALS", raising=False)
    assert not fcm.is_configured()
    assert fcm.send(["token"], title="t", body="b", data={}) == PushResult(0, ())


def test_the_inbox_and_the_device_api(world, sent, django_capture_on_commit_callbacks):
    client = APIClient()
    client.force_authenticate(world["ana"])
    assert (
        client.post(
            "/api/notifications/devices/", {"token": "t1", "app_version": "1.0.0"}, format="json"
        ).status_code
        == 204
    )
    # The same phone signed in with another account moves to it.
    other = APIClient()
    other.force_authenticate(world["luis"])
    other.post("/api/notifications/devices/", {"token": "t1"}, format="json")
    assert PushDevice.objects.get(token="t1").user == world["luis"]

    assign(world, django_capture_on_commit_callbacks)
    inbox = client.get("/api/notifications/").json()
    assert inbox["unread"] == 1
    assert inbox["results"][0]["title"] == "Nueva tarea en Danza 1A"
    assert inbox["results"][0]["read"] is False
    assert client.post("/api/notifications/read/", {}, format="json").json() == {"updated": 1}
    assert client.get("/api/notifications/").json()["unread"] == 0
    # Nobody reads or clears another person's inbox.
    assert other.post("/api/notifications/read/", {}, format="json").json() == {"updated": 1}
    assert Notification.objects.filter(read_at__isnull=True).count() == 0

    other.post("/api/notifications/devices/remove/", {"token": "t1"}, format="json")
    assert not PushDevice.objects.exists()
    assert APIClient().get("/api/notifications/").status_code == 401


def test_signal_receivers_pass_the_debug_check():
    """With DEBUG on, Django refuses receivers without **kwargs at startup."""
    from django.utils.inspect import func_accepts_kwargs

    from apps.notifications import signals

    for receiver in (signals.assignment_created, signals.session_note_created, signals.game_saved):
        assert func_accepts_kwargs(receiver)
