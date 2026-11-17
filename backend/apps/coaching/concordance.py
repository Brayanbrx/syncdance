"""How well the app's score agrees with the instructor (pilot gate, E5).

Spearman rank correlation between the instructor's 1-5 rating and the app's
similarity on the same practices. Only comparable practices count: normal
speed and enough evaluated time, as in the student's progress. With fewer than
MIN_PAIRS pairs there is no figure (None), never a guess.
"""

from .models import PracticeRating

MIN_PAIRS = 5
MIN_COVERAGE = 0.5  # same provisional floor as routine progress


def _ranks(values):
    """Average ranks (1-based); ties share the mean of their positions."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return ranks


def spearman(pairs):
    """Rank correlation of (x, y) pairs; None without enough data or spread."""
    if len(pairs) < MIN_PAIRS:
        return None
    xs = _ranks([x for x, _ in pairs])
    ys = _ranks([y for _, y in pairs])
    mean_x, mean_y = sum(xs) / len(xs), sum(ys) / len(ys)
    cov = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys, strict=True))
    var_x = sum((x - mean_x) ** 2 for x in xs)
    var_y = sum((y - mean_y) ** 2 for y in ys)
    if var_x == 0 or var_y == 0:
        return None
    return cov / (var_x * var_y) ** 0.5


def concordance(ratings=None):
    """{"pairs": n, "spearman": rho or None} over comparable rated practices."""
    ratings = PracticeRating.objects.all() if ratings is None else ratings
    pairs = list(
        ratings.filter(
            session__playback_speed=1.0,
            session__quality_ratio__gte=MIN_COVERAGE,
            session__pose_score__isnull=False,
        ).values_list("rating", "session__pose_score")
    )
    rho = spearman(pairs)
    return {"pairs": len(pairs), "spearman": None if rho is None else round(rho, 3)}
