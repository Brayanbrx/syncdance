"""Compile 8-count blocks into a continuous coach pose over time."""

import math
from dataclasses import dataclass

from .body import ANKLE_HEIGHT, HIP_HALF, SHIN, STAND_HEIGHT, THIGH, Arm, Pose
from .steps import Arms, Block, Legs

BOUNCE = 0.03  # knees soften on every beat
INTRO_BOUNCE = 0.012
STEP_ARC = 0.07  # a stepping foot lifts instead of sliding


def _smooth(s):
    return s * s * (3 - 2 * s)


def _lerp(a, b, s):
    return a + (b - a) * s


def _lerp3(a, b, s):
    return (_lerp(a[0], b[0], s), _lerp(a[1], b[1], s), _lerp(a[2], b[2], s))


def _foot(a, b, s):
    point = _lerp3(a, b, s)
    moved = math.hypot(b[0] - a[0], b[2] - a[2]) > 0.04
    on_floor = a[1] < ANKLE_HEIGHT + 0.03 and b[1] < ANKLE_HEIGHT + 0.03
    if moved and on_floor:
        point = (point[0], point[1] + STEP_ARC * math.sin(math.pi * s), point[2])
    return point


def _planted(foot):
    return foot[1] < ANKLE_HEIGHT + 0.03


def _pelvis_height(base, pelvis_x, legs):
    """A dancer lowers the hips to spread the feet: planted feet always reach."""
    height = base
    reach = THIGH + SHIN - 0.002
    for foot, side in ((legs.r, 1), (legs.l, -1)):
        if not _planted(foot):
            continue
        dx = foot[0] - (pelvis_x + side * HIP_HALF)
        vertical = math.sqrt(max(reach**2 - dx**2 - foot[2] ** 2, 0.0))
        height = min(height, foot[1] + vertical)
    return height


def _arm(a, b, s):
    return Arm(
        _lerp(a.raise_deg, b.raise_deg, s),
        _lerp(a.forward_deg, b.forward_deg, s),
        _lerp(a.elbow_deg, b.elbow_deg, s),
        _lerp3(a.bend, b.bend, s),
    )


def _at(keys, beat, blend):
    """Smoothstep between the surrounding keyframes; hold at both ends."""
    if beat <= keys[0][0]:
        return keys[0][1]
    for (b0, v0), (b1, v1) in zip(keys, keys[1:], strict=False):
        if beat <= b1:
            return blend(v0, v1, _smooth((beat - b0) / (b1 - b0)))
    return keys[-1][1]


@dataclass(frozen=True)
class Cue:
    caption: str
    count: int  # 1..8 inside a block; 5..8 during the lead-in
    next_caption: str | None
    evaluated: bool


class Timeline:
    def __init__(self, blocks, bpm):
        if not 60 <= bpm <= 180:
            raise ValueError("BPM fuera de rango.")
        self.bpm = bpm
        self.blocks = tuple(blocks)
        self.spans = []  # (start_beat, block)
        start = 0
        legs, arms = [], []
        for block in self.blocks:
            self.spans.append((start, block))
            legs.extend((start + beat, value) for beat, value in block.legs)
            arms.extend((start + beat, value) for beat, value in block.arms)
            start += block.beats
        self.total_beats = start
        self._legs = sorted(legs, key=lambda kv: kv[0])
        self._arms = sorted(arms, key=lambda kv: kv[0])

    @property
    def seconds_per_beat(self):
        return 60 / self.bpm

    @property
    def duration_s(self):
        return self.total_beats * self.seconds_per_beat

    def beat_at(self, seconds):
        return seconds / self.seconds_per_beat

    def _span(self, beat):
        for index, (start, block) in enumerate(self.spans):
            if beat < start + block.beats:
                return index, start, block
        index = len(self.spans) - 1
        return index, *self.spans[index]

    def evaluated_at(self, seconds):
        _, _, block = self._span(self.beat_at(seconds))
        return block.key != "intro"

    def pose_at(self, seconds):
        beat = self.beat_at(seconds)
        legs = _at(
            self._legs,
            beat,
            lambda a, b, s: Legs(_foot(a.r, b.r, s), _foot(a.l, b.l, s)),
        )
        arms = _at(self._arms, beat, lambda a, b, s: Arms(_arm(a.r, b.r, s), _arm(a.l, b.l, s)))
        depth = INTRO_BOUNCE if not self.evaluated_at(seconds) else BOUNCE
        # Deepest exactly on the beat, like a dancer marking the count.
        drop = depth * (0.5 + 0.5 * math.cos(2 * math.pi * beat))
        height = _pelvis_height(STAND_HEIGHT - drop, legs.pelvis_x, legs)
        return Pose(
            pelvis=(legs.pelvis_x, height, 0.0),
            left_foot=legs.r,  # screen right is the coach's anatomical left
            right_foot=legs.l,
            left_arm=arms.r,
            right_arm=arms.l,
        )

    def cue_at(self, seconds):
        beat = self.beat_at(seconds)
        index, start, block = self._span(beat)
        within = int(beat - start)
        intro = block.key == "intro"
        count = (8 - block.beats + within + 1) if intro else within + 1
        next_caption = None
        if index + 1 < len(self.spans) and within >= block.beats - 2:
            following = self.spans[index + 1][1]
            if following.key != block.key:
                next_caption = following.caption
        return Cue(block.caption, min(count, 8), next_caption, not intro)


def compile_blocks(blocks: list[Block], bpm: int) -> Timeline:
    return Timeline(blocks, bpm)
