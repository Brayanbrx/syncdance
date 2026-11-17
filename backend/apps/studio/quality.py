"""How usable an instructor's master video turned out, from its reference.

Every reference sample says whether exactly one person was measurable
(SINGLE_PERSON). The phone only compares against those samples, so a video
with long gaps teaches little: the studio shows where they are before the
instructor publishes.
"""

import gzip
import io
import json
from collections import Counter

from django.core.cache import cache

VERSION = "quality-report-v1"
# Provisional until the physical validation (E2): share of usable samples
# needed to publish, and the shortest gap worth pointing out.
MIN_USABLE_RATIO = 0.8
MIN_PROBLEM_MS = 1000
MAX_COMPRESSED_BYTES = 12 * 1024 * 1024
MAX_EXPANDED_BYTES = 96 * 1024 * 1024
USABLE = "SINGLE_PERSON"


def quality_report(reference) -> dict | None:
    """Report of a READY reference; None when there is nothing to measure."""
    if reference is None or reference.status != "READY" or not reference.reference_asset:
        return None
    if reference.feature_schema != "motion-features-v1":
        return None  # a melody has no pose to report on
    key = f"studio:{VERSION}:{reference.pk}:{reference.checksum_sha256}"
    report = cache.get(key)
    if report is None:
        report = summarize(_read_artifact(reference))
        cache.set(key, report, 24 * 60 * 60)
    return report


def _read_artifact(reference) -> dict:
    with reference.reference_asset.open("rb") as stored:
        compressed = stored.read(MAX_COMPRESSED_BYTES + 1)
    if len(compressed) > MAX_COMPRESSED_BYTES:
        return {}
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as unpacked:
        raw = unpacked.read(MAX_EXPANDED_BYTES + 1)
    if len(raw) > MAX_EXPANDED_BYTES:
        return {}
    return json.loads(raw)


def summarize(artifact: dict) -> dict:
    frames = [f for f in artifact.get("frames") or [] if isinstance(f, dict)]
    rate = artifact.get("sample_rate_hz") or 12
    sample_ms = round(1000 / rate)
    counts = Counter(frame.get("quality") for frame in frames)
    total = len(frames)

    def share(kind):
        # No samples: unknown, never 0 %.
        return round(counts[kind] / total, 3) if total else None

    problems, gap = [], []
    for frame in [*frames, {"quality": USABLE}]:  # sentinel closes the last gap
        if frame.get("quality") != USABLE:
            gap.append(frame)
            continue
        if gap:
            start, end = gap[0]["t"], gap[-1]["t"] + sample_ms
            if end - start >= MIN_PROBLEM_MS:
                kind = Counter(g.get("quality") for g in gap).most_common(1)[0][0]
                problems.append({"start_ms": start, "end_ms": end, "kind": kind})
            gap = []
    usable = share(USABLE)
    return {
        "version": VERSION,
        "samples": total,
        "duration_ms": artifact.get("duration_ms"),
        "single_person": usable,
        "no_usable_pose": share("NO_USABLE_POSE"),
        "multiple_people": share("MULTIPLE_PEOPLE"),
        "problems": problems,
        "min_usable_ratio": MIN_USABLE_RATIO,
        "publishable": usable is not None and usable >= MIN_USABLE_RATIO,
    }
