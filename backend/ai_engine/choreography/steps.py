"""Standard step vocabulary as data: 8-count blocks in screen terms.

`r`/`l` mean screen right/left: the learner's right/left in mirror mode, and
the coach's anatomical left/right. Steps stay facing the camera and move
mostly sideways or with the arms, which a frontal 2D camera measures well;
turns, mambo and body rolls are left out on purpose.
"""

from dataclasses import dataclass

from .body import ANKLE_HEIGHT, FOOT, Arm

FLOOR = ANKLE_HEIGHT

# Arm presets (both arms unless a step mixes them).
DOWN = Arm(8, 0, 6)
V_UP = Arm(150, 0, 4)
T = Arm(90, 0, 0)
GOAL = Arm(90, 0, 95)  # elbows at shoulder height, forearms up
CLAP = Arm(18, 72, 58, bend=(-1.0, 0.0, 0.0))  # hands meet in front of the chest


@dataclass(frozen=True)
class Legs:
    """Ankle positions (x, height, forward) for screen right and left feet."""

    r: tuple[float, float, float] = (FOOT, FLOOR, 0.0)
    l: tuple[float, float, float] = (-FOOT, FLOOR, 0.0)  # noqa: E741

    @property
    def pelvis_x(self):
        return (self.r[0] + self.l[0]) / 2


@dataclass(frozen=True)
class Arms:
    r: Arm = DOWN
    l: Arm = DOWN  # noqa: E741


@dataclass(frozen=True)
class Block:
    """One 8-count phrase; keys are beats 0..7 (counts 1..8)."""

    key: str
    caption: str  # ASCII: the coach video uses Hershey fonts
    legs: tuple[tuple[float, Legs], ...]
    arms: tuple[tuple[float, Arms], ...]
    beats: int = 8


NEUTRAL = Legs()


def together(center):
    return Legs((center + FOOT, FLOOR, 0.0), (center - FOOT, FLOOR, 0.0))


def _step_touch_legs():
    """Step R, touch L; step L, touch R. Sways between centres -0.15 and +0.15."""
    wide_right = Legs((0.26, FLOOR, 0.0), (-0.11, FLOOR, 0.0))
    right = Legs((0.26, FLOOR, 0.0), (0.04, FLOOR + 0.02, 0.0))
    wide_left = Legs((0.26, FLOOR, 0.0), (-0.26, FLOOR, 0.0))
    left = Legs((-0.04, FLOOR + 0.02, 0.0), (-0.26, FLOOR, 0.0))
    wide_right_again = Legs((0.26, FLOOR, 0.0), (-0.26, FLOOR, 0.0))
    return (
        (0, wide_right),
        (1, right),
        (2, wide_left),
        (3, left),
        (4, wide_right_again),
        (5, right),
        (6, wide_left),
        (7, left),
    )


def _alternate(first, second, beats=8):
    return tuple((beat, first if beat % 2 == 0 else second) for beat in range(beats))


def marcha():
    legs = []
    for beat in range(8):
        legs.append((beat, NEUTRAL))
        lifted = (FOOT, FLOOR + 0.17, 0.12) if beat % 2 == 0 else (-FOOT, FLOOR + 0.17, 0.12)
        up = Legs(lifted, NEUTRAL.l) if beat % 2 == 0 else Legs(NEUTRAL.r, lifted)
        legs.append((beat + 0.5, up))
    return Block(
        "marcha",
        "MARCHA CON BRAZOS",
        tuple(legs),
        _alternate(Arms(V_UP, V_UP), Arms(DOWN, DOWN)),
    )


def step_touch_palmada():
    return Block(
        "step-touch-palmada",
        "STEP TOUCH + PALMADA",
        _step_touch_legs(),
        _alternate(Arms(T, T), Arms(CLAP, CLAP)),
    )


def step_touch_v():
    return Block(
        "step-touch-v",
        "STEP TOUCH + BRAZOS EN V",
        _step_touch_legs(),
        _alternate(Arms(V_UP, V_UP), Arms(DOWN, DOWN)),
    )


def rodilla_arriba():
    knee_r = Legs((FOOT, FLOOR + 0.36, 0.30), NEUTRAL.l)
    knee_l = Legs(NEUTRAL.r, (-FOOT, FLOOR + 0.36, 0.30))
    legs = ((0, knee_r), (1, NEUTRAL), (2, knee_l), (3, NEUTRAL))
    legs = legs + tuple((beat + 4, value) for beat, value in legs)
    return Block(
        "rodilla-arriba",
        "RODILLA ARRIBA",
        legs,
        _alternate(Arms(GOAL, GOAL), Arms(V_UP, V_UP)),
    )


def toque_lateral():
    tap_r = Legs((0.45, FLOOR + 0.01, 0.0), NEUTRAL.l)
    tap_l = Legs(NEUTRAL.r, (-0.45, FLOOR + 0.01, 0.0))
    legs = ((0, tap_r), (1, NEUTRAL), (2, tap_l), (3, NEUTRAL))
    legs = legs + tuple((beat + 4, value) for beat, value in legs)
    arms = (
        (0, Arms(T, DOWN)),
        (1, Arms(DOWN, DOWN)),
        (2, Arms(DOWN, T)),
        (3, Arms(DOWN, DOWN)),
    )
    arms = arms + tuple((beat + 4, value) for beat, value in arms)
    return Block("toque-lateral", "TOQUE LATERAL", legs, arms)


def intro(beats=4):
    """Lead-in '5, 6, 7, 8': neutral stance, not evaluated."""
    # Hold still until half a beat before count 1, then move into the first step.
    hold = beats - 0.5
    return Block(
        "intro",
        "LISTOS",
        ((0, NEUTRAL), (hold, NEUTRAL)),
        ((0, Arms(DOWN, DOWN)), (hold, Arms(DOWN, DOWN))),
        beats=beats,
    )


STEPS = {
    block().key: block
    for block in (marcha, step_touch_palmada, step_touch_v, rodilla_arriba, toque_lateral)
}
