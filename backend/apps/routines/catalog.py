"""Default dance catalog: free-license masters downloaded from their source.

The manifest (data/default_catalog.json) holds only metadata, provenance and
SHA-256 pins. Videos are fetched at install time, never committed: the Mixkit
license allows free use without attribution but not redistributing raw files.
"""

import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.db import transaction

from ai_engine.pose.reference import MAX_SOURCE_BYTES

from .models import Routine
from .services import create_routine

MANIFEST = Path(__file__).resolve().parent / "data" / "default_catalog.json"
ALLOWED_HOSTS = {"assets.mixkit.co"}
CATALOG_USERNAME = "catalogo"
REQUIRED = ("key", "name", "style", "difficulty", "description", "video_url")
PROVENANCE = ("source_url", "license_name", "credit", "sha256")


class CatalogError(Exception):
    """A manifest or download problem; the message is safe to print."""


def load_manifest(path=MANIFEST):
    entries = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not entries:
        raise CatalogError("El manifiesto debe ser una lista no vacía.")
    keys = set()
    for entry in entries:
        missing = [field for field in REQUIRED + PROVENANCE if not entry.get(field)]
        if missing:
            raise CatalogError(f"{entry.get('key', '?')}: faltan {', '.join(missing)}.")
        if entry["key"] in keys:
            raise CatalogError(f"Clave duplicada: {entry['key']}.")
        if entry["difficulty"] not in Routine.Difficulty.values:
            raise CatalogError(f"{entry['key']}: dificultad no válida.")
        _check_url(entry["video_url"])
        keys.add(entry["key"])
    return entries


def _check_url(url):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise CatalogError(f"Origen no permitido: {url}")


def download(url, *, expected_sha256, opener=urlopen):
    """Stream with a size cap and verify the pinned hash before use."""
    _check_url(url)
    digest = hashlib.sha256()
    chunks = []
    total = 0
    request = Request(url, headers={"User-Agent": "SyncDance-catalog/1"})
    with opener(request, timeout=60) as response:
        while chunk := response.read(1024 * 1024):
            total += len(chunk)
            if total > MAX_SOURCE_BYTES:
                raise CatalogError(f"El video supera el límite: {url}")
            digest.update(chunk)
            chunks.append(chunk)
    if digest.hexdigest() != expected_sha256:
        raise CatalogError(f"SHA-256 distinto del fijado en el manifiesto: {url}")
    return b"".join(chunks)


def catalog_instructor():
    User = get_user_model()
    user, created = User.objects.get_or_create(
        username=CATALOG_USERNAME,
        defaults={
            "email": "catalogo@syncdance.local",
            "role": User.Role.INSTRUCTOR,
        },
    )
    if created:
        user.set_unusable_password()
        user.save(update_fields=["password"])
    return user


def install(entries, *, fetch=download, only=None, log=print):
    """Create missing catalog routines; existing keys are left untouched."""
    instructor = catalog_instructor()
    created = 0
    for entry in entries:
        key = entry["key"]
        if only and key not in only:
            continue
        if Routine.objects.filter(catalog_key=key).exists():
            log(f"= {key}: ya instalada")
            continue
        data = fetch(entry["video_url"], expected_sha256=entry["sha256"])
        with transaction.atomic():
            create_routine(
                instructor=instructor,
                name=entry["name"],
                description=entry["description"],
                difficulty=entry["difficulty"],
                style=entry["style"],
                catalog_key=key,
                source_url=entry["source_url"],
                license_name=entry["license_name"],
                credit=entry["credit"],
                master_video=ContentFile(data, name=f"{key}.mp4"),
            )
        created += 1
        log(f"+ {key}: instalada; referencia encolada")
    return created
