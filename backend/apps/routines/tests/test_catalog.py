import hashlib
import io
import json

import pytest

from apps.routines import catalog
from apps.routines.models import Routine, RoutineReference

pytestmark = pytest.mark.django_db
VIDEO = b"fake mp4 bytes"


def entry(key="hip-hop-1", **overrides):
    return {
        "key": key,
        "name": "Hip hop urbano",
        "style": "Hip hop",
        "difficulty": "BEGINNER",
        "description": "Coreografía corta de una bailarina.",
        "video_url": f"https://assets.mixkit.co/videos/1/{key}-720.mp4",
        "source_url": "https://mixkit.co/free-stock-video/demo-1/",
        "license_name": "Mixkit Stock Video Free License",
        "credit": "Mixkit",
        "sha256": hashlib.sha256(VIDEO).hexdigest(),
        **overrides,
    }


def fetch(url, *, expected_sha256):
    assert expected_sha256 == hashlib.sha256(VIDEO).hexdigest()
    return VIDEO


@pytest.fixture(autouse=True)
def no_worker(monkeypatch):
    # Reference generation is the normal pipeline; here only its queueing matters.
    monkeypatch.setattr("apps.routines.reference_services._dispatch", lambda pk: None)


def test_install_creates_routines_with_provenance_and_queues_references(
    django_capture_on_commit_callbacks,
):
    with django_capture_on_commit_callbacks(execute=True):
        created = catalog.install([entry(), entry("ballet-1", style="Ballet")], fetch=fetch)
    assert created == 2
    routine = Routine.objects.get(catalog_key="hip-hop-1")
    assert routine.style == "Hip hop"
    assert routine.license_name == "Mixkit Stock Video Free License"
    assert routine.source_url.startswith("https://mixkit.co/")
    assert routine.master_video.read() == VIDEO
    assert routine.instructor.username == catalog.CATALOG_USERNAME
    assert not routine.instructor.has_usable_password()
    assert RoutineReference.objects.filter(routine=routine, status="PENDING").count() == 1


def test_install_is_idempotent_and_respects_only():
    catalog.install([entry()], fetch=fetch)
    calls = []

    def counting(url, *, expected_sha256):
        calls.append(url)
        return VIDEO

    assert catalog.install([entry(), entry("ballet-1")], fetch=counting, only=["ballet-1"]) == 1
    assert catalog.install([entry(), entry("ballet-1")], fetch=counting) == 0
    assert len(calls) == 1
    assert Routine.objects.count() == 2


def test_download_rejects_other_hosts_hash_mismatch_and_oversize(monkeypatch):
    def opener(chunks):
        return lambda request, timeout: io.BytesIO(b"".join(chunks))

    with pytest.raises(catalog.CatalogError, match="Origen"):
        catalog.download("http://assets.mixkit.co/v.mp4", expected_sha256="0" * 64)
    with pytest.raises(catalog.CatalogError, match="Origen"):
        catalog.download("https://example.com/v.mp4", expected_sha256="0" * 64)
    with pytest.raises(catalog.CatalogError, match="SHA-256"):
        catalog.download(
            "https://assets.mixkit.co/v.mp4", expected_sha256="0" * 64, opener=opener([VIDEO])
        )
    good = catalog.download(
        "https://assets.mixkit.co/v.mp4",
        expected_sha256=hashlib.sha256(VIDEO).hexdigest(),
        opener=opener([VIDEO]),
    )
    assert good == VIDEO
    monkeypatch.setattr(catalog, "MAX_SOURCE_BYTES", 4)
    with pytest.raises(catalog.CatalogError, match="límite"):
        catalog.download(
            "https://assets.mixkit.co/v.mp4",
            expected_sha256=hashlib.sha256(VIDEO).hexdigest(),
            opener=opener([VIDEO]),
        )


def test_failed_download_creates_nothing():
    def broken(url, *, expected_sha256):
        raise catalog.CatalogError("SHA-256 distinto")

    with pytest.raises(catalog.CatalogError):
        catalog.install([entry()], fetch=broken)
    assert Routine.objects.count() == 0


@pytest.mark.parametrize(
    "change",
    [
        {"sha256": ""},
        {"license_name": ""},
        {"difficulty": "EXPERT"},
        {"video_url": "https://youtube.com/watch?v=x"},
    ],
)
def test_manifest_validation(tmp_path, change):
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps([entry(**change)]), encoding="utf-8")
    with pytest.raises(catalog.CatalogError):
        catalog.load_manifest(path)


def test_manifest_rejects_duplicate_keys(tmp_path):
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps([entry(), entry()]), encoding="utf-8")
    with pytest.raises(catalog.CatalogError, match="duplicada"):
        catalog.load_manifest(path)


def test_shipped_manifest_is_valid():
    entries = catalog.load_manifest()
    assert len(entries) >= 5
    assert all(e["license_name"] and e["credit"] and len(e["sha256"]) == 64 for e in entries)
