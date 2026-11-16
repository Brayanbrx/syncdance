import hashlib

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.backoffice.models import AppRelease
from apps.coaching.models import Course
from apps.routines.models import Routine

pytestmark = pytest.mark.django_db

APK = b"PK\x03\x04" + b"fake android package" * 10


@pytest.fixture(autouse=True)
def media(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path


@pytest.fixture
def people():
    return {
        "root": User.objects.create_superuser(username="root", email="r@example.com", password="x"),
        "admin": User.objects.create_user(
            username="jefa", email="j@example.com", password="x", role="ADMIN"
        ),
        "teacher": User.objects.create_user(
            username="profe", email="p@example.com", password="x", role="INSTRUCTOR"
        ),
        "student": User.objects.create_user(username="ana", email="a@example.com", password="x"),
    }


def client_for(user=None):
    client = APIClient()
    if user:
        client.force_authenticate(user)
    return client


def upload(client, code=1, name="1.0.0", publish=True, content=APK, filename="app.apk"):
    return client.post(
        "/api/panel/releases/",
        {
            "version_name": name,
            "version_code": code,
            "notes": "Primera versión",
            "is_published": "true" if publish else "false",
            "apk": SimpleUploadedFile(filename, content),
        },
        format="multipart",
    )


def test_landing_offers_the_newest_published_apk(people):
    anonymous = client_for()
    assert anonymous.get("/api/app/latest/").status_code == 404
    assert anonymous.get("/api/app/download/").status_code == 404

    admin = client_for(people["admin"])
    assert upload(admin, code=1, name="1.0.0").status_code == 201
    assert upload(admin, code=3, name="1.2.0", publish=False).status_code == 201
    assert upload(admin, code=2, name="1.1.0", content=APK + b"v2").status_code == 201

    latest = anonymous.get("/api/app/latest/")
    assert latest.status_code == 200
    # 1.2.0 is not published: 1.1.0 is the newest one people can get.
    assert latest.data["version_name"] == "1.1.0"
    assert latest.data["size_bytes"] == len(APK) + 2
    assert latest.data["sha256"] == hashlib.sha256(APK + b"v2").hexdigest()
    assert latest.data["download_url"] == "/api/app/download/"
    assert "uploaded_by" not in latest.data

    download = anonymous.get("/api/app/download/")
    assert download.status_code == 200
    assert download["Content-Type"] == "application/vnd.android.package-archive"
    assert 'filename="SyncDance-1.1.0.apk"' in download["Content-Disposition"]
    assert b"".join(download.streaming_content) == APK + b"v2"
    download.close()


def test_only_real_apks_are_accepted(people):
    admin = client_for(people["admin"])
    not_zip = upload(admin, content=b"MZ not an apk")
    assert not_zip.status_code == 400
    assert "apk" in not_zip.data
    wrong_name = upload(admin, filename="app.zip")
    assert wrong_name.status_code == 400
    assert upload(admin, code=1).status_code == 201
    assert upload(admin, code=1).status_code == 400  # version codes are unique
    assert AppRelease.objects.count() == 1


def test_publishing_and_deleting_releases(people):
    admin = client_for(people["admin"])
    release_id = upload(admin, publish=False).data["id"]
    assert client_for().get("/api/app/latest/").status_code == 404
    published = admin.patch(f"/api/panel/releases/{release_id}/", {"is_published": True})
    assert published.status_code == 200
    assert published.data["published_at"]
    # A published build is never deleted by accident.
    assert admin.delete(f"/api/panel/releases/{release_id}/").status_code == 400
    admin.patch(f"/api/panel/releases/{release_id}/", {"is_published": False})
    assert admin.delete(f"/api/panel/releases/{release_id}/").status_code == 204
    assert not AppRelease.objects.exists()


@pytest.mark.parametrize("who", [None, "student", "teacher"])
def test_the_panel_is_only_for_platform_admins(people, who):
    client = client_for(people[who] if who else None)
    expected = 401 if who is None else 403
    for url in (
        "/api/panel/summary/",
        "/api/panel/users/",
        "/api/panel/routines/",
        "/api/panel/courses/",
        "/api/panel/releases/",
    ):
        assert client.get(url).status_code == expected, url


def test_me_tells_the_web_who_may_open_the_panel(people):
    for who, expected in (("root", True), ("admin", True), ("teacher", False), ("student", False)):
        me = client_for(people[who]).get("/api/auth/me/")
        assert me.data["is_platform_admin"] is expected, who


def test_summary_counts(people):
    routine = Routine.objects.create(
        name="Paso", instructor=people["teacher"], difficulty="BEGINNER"
    )
    Course.objects.create(name="Danza", instructor=people["teacher"])
    summary = client_for(people["root"]).get("/api/panel/summary/").data
    assert summary["users"]["students"] == 1
    assert summary["users"]["instructors"] == 1
    assert summary["catalog"]["routines"] == 1
    assert summary["courses"]["courses"] == 1
    assert summary["latest_release"] is None
    assert routine.pk


def test_users_filter_promote_and_reset_password(people):
    admin = client_for(people["admin"])
    students = admin.get("/api/panel/users/", {"role": "STUDENT"}).data["results"]
    assert [u["username"] for u in students] == ["ana"]
    found = admin.get("/api/panel/users/", {"search": "PROF"}).data["results"]
    assert [u["username"] for u in found] == ["profe"]

    ana = people["student"]
    promoted = admin.patch(f"/api/panel/users/{ana.pk}/", {"role": "INSTRUCTOR"})
    assert promoted.status_code == 200
    ana.refresh_from_db()
    assert ana.is_staff
    demoted = admin.patch(f"/api/panel/users/{ana.pk}/", {"role": "STUDENT"})
    assert demoted.status_code == 200
    ana.refresh_from_db()
    assert not ana.is_staff  # back to student: no Django Admin access

    weak = admin.post(f"/api/panel/users/{ana.pk}/set-password/", {"password": "12345678"})
    assert weak.status_code == 400
    ok = admin.post(f"/api/panel/users/{ana.pk}/set-password/", {"password": "Baile-segur0"})
    assert ok.status_code == 204
    ana.refresh_from_db()
    assert ana.check_password("Baile-segur0")


def test_nobody_locks_themselves_out_or_touches_a_superuser(people):
    admin = client_for(people["admin"])
    me = people["admin"].pk
    assert admin.patch(f"/api/panel/users/{me}/", {"is_active": False}).status_code == 400
    assert admin.patch(f"/api/panel/users/{me}/", {"role": "STUDENT"}).status_code == 400
    assert admin.patch(f"/api/panel/users/{me}/", {"first_name": "Jefa"}).status_code == 200
    root = people["root"].pk
    assert admin.patch(f"/api/panel/users/{root}/", {"is_active": False}).status_code == 403
    assert (
        admin.post(
            f"/api/panel/users/{root}/set-password/", {"password": "Otra-clave9"}
        ).status_code
        == 403
    )


def test_create_an_instructor_account(people):
    admin = client_for(people["admin"])
    response = admin.post(
        "/api/panel/users/",
        {
            "username": "rosa",
            "email": "rosa@example.com",
            "password": "Salsa-2026-ok",
            "role": "INSTRUCTOR",
            "first_name": "Rosa",
        },
    )
    assert response.status_code == 201
    rosa = User.objects.get(username="rosa")
    assert rosa.role == "INSTRUCTOR" and rosa.is_staff and rosa.check_password("Salsa-2026-ok")
    weak = admin.post(
        "/api/panel/users/",
        {"username": "x", "email": "x@example.com", "password": "password", "role": "STUDENT"},
    )
    assert weak.status_code == 400
    assert "password" in weak.data


def test_routines_can_be_hidden_from_the_catalog(people):
    routine = Routine.objects.create(
        name="Paso", instructor=people["teacher"], difficulty="BEGINNER"
    )
    admin = client_for(people["admin"])
    listing = admin.get("/api/panel/routines/").data["results"]
    assert listing[0]["reference_status"] is None
    assert listing[0]["sessions"] == 0
    hidden = admin.patch(f"/api/panel/routines/{routine.pk}/", {"is_active": False, "name": "X"})
    assert hidden.status_code == 200
    routine.refresh_from_db()
    assert routine.is_active is False
    assert routine.name == "Paso"  # everything else is read-only here
