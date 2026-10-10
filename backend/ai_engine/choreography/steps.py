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
BENT = Arm(28, 20, 85)  # relaxed urban arms, elbows bent
SWING_OUT = Arm(60, 10, 70)  # this arm reaches toward the step
SWING_IN = Arm(22, 45, 105, bend=(-1.0, 0.0, 0.0))  # this arm crosses the chest
ELBOWS_DOWN = Arm(25, 0, 110)  # shoulder pump: elbows tucked, hands up


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
    caption: str  # shown in the coach video; accents need the TTF font
    legs: tuple[tuple[float, Legs], ...]
    arms: tuple[tuple[float, Arms], ...]
    beats: int = 8
    bounce: float | None = None  # knee bounce depth; None keeps the default


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
        "¡LISTOS!",
        ((0, NEUTRAL), (hold, NEUTRAL)),
        ((0, Arms(DOWN, DOWN)), (hold, Arms(DOWN, DOWN))),
        beats=beats,
    )


def _repeat_half(keys):
    """Counts 5-8 repeat counts 1-4."""
    return keys + tuple((beat + 4, value) for beat, value in keys)


# Level 2: travelling and footwork.


def _grapevine_legs():
    """Side, behind, side, touch to the right; then the same to the left.
    Steps stay short so the coach (arms open) never leaves the frame."""
    return (
        (0, Legs((0.28, FLOOR, 0.0), (-0.11, FLOOR, 0.0))),  # step R side
        (1, Legs((0.28, FLOOR, 0.0), (0.34, FLOOR, -0.15))),  # L crosses behind
        (2, Legs((0.50, FLOOR, 0.0), (0.34, FLOOR, -0.15))),  # step R side
        (3, Legs((0.50, FLOOR, 0.0), (0.30, FLOOR + 0.02, 0.0))),  # touch L
        (4, Legs((0.50, FLOOR, 0.0), (0.06, FLOOR, 0.0))),  # step L side
        (5, Legs((-0.02, FLOOR, -0.15), (0.06, FLOOR, 0.0))),  # R crosses behind
        (6, Legs((-0.02, FLOOR, -0.15), (-0.20, FLOOR, 0.0))),  # step L side
        (7, Legs((0.02, FLOOR + 0.02, 0.0), (-0.20, FLOOR, 0.0))),  # touch R
    )


def grapevine():
    arms = _repeat_half(((0, Arms(T, T)), (1, Arms(T, T)), (2, Arms(T, T)), (3, Arms(CLAP, CLAP))))
    return Block("grapevine", "GRAPEVINE (VID)", _grapevine_legs(), arms)


def v_step():
    out_r = Legs((0.30, FLOOR, 0.22), NEUTRAL.l)
    out_both = Legs((0.30, FLOOR, 0.22), (-0.30, FLOOR, 0.22))
    back_r = Legs(NEUTRAL.r, (-0.30, FLOOR, 0.22))
    legs = _repeat_half(((0, out_r), (1, out_both), (2, back_r), (3, NEUTRAL)))
    arms = _repeat_half(
        (
            (0, Arms(V_UP, DOWN)),
            (1, Arms(V_UP, V_UP)),
            (2, Arms(DOWN, V_UP)),
            (3, Arms(DOWN, DOWN)),
        )
    )
    return Block("v-step", "V-STEP", legs, arms)


def box_step():
    cross = Legs((-0.08, FLOOR, 0.15), NEUTRAL.l)  # R crosses in front
    back = Legs((-0.08, FLOOR, 0.15), (-0.15, FLOOR, -0.18))  # L steps back
    side = Legs((0.22, FLOOR, -0.05), (-0.15, FLOOR, -0.18))  # R steps side
    legs = _repeat_half(((0, cross), (1, back), (2, side), (3, NEUTRAL)))
    arms = _repeat_half(
        (
            (0, Arms(CLAP, CLAP)),
            (1, Arms(T, T)),
            (2, Arms(V_UP, V_UP)),
            (3, Arms(DOWN, DOWN)),
        )
    )
    return Block("box-step", "BOX STEP", legs, arms)


def step_touch_doble():
    """Two step touches to the right, two to the left; ends centred."""
    legs = (
        (0, Legs((0.26, FLOOR, 0.0), (-0.11, FLOOR, 0.0))),
        (1, together(0.15)),
        (2, Legs((0.41, FLOOR, 0.0), (0.04, FLOOR, 0.0))),
        (3, together(0.30)),
        (4, Legs((0.41, FLOOR, 0.0), (0.04, FLOOR, 0.0))),
        (5, together(0.15)),
        (6, Legs((0.26, FLOOR, 0.0), (-0.11, FLOOR, 0.0))),
        (7, together(0.0)),
    )
    arms = _repeat_half(
        (
            (0, Arms(V_UP, V_UP)),
            (1, Arms(DOWN, DOWN)),
            (2, Arms(V_UP, V_UP)),
            (3, Arms(CLAP, CLAP)),
        )
    )
    return Block("step-touch-doble", "STEP TOUCH DOBLE", legs, arms)


# Level 3: urban rhythm.


def two_step():
    arms = (
        (0, Arms(SWING_OUT, SWING_IN)),
        (1, Arms(BENT, BENT)),
        (2, Arms(SWING_IN, SWING_OUT)),
        (3, Arms(BENT, BENT)),
    )
    return Block(
        "two-step",
        "TWO-STEP CON REBOTE",
        _step_touch_legs(),
        _repeat_half(arms),
        bounce=0.05,
    )


def kick_ball_change():
    """Kick, step back on the ball of the foot (&), change weight in place."""
    kick_r = Legs((FOOT, FLOOR + 0.22, 0.32), NEUTRAL.l)
    ball_r = Legs((0.13, FLOOR, -0.08), NEUTRAL.l)
    kick_l = Legs(NEUTRAL.r, (-FOOT, FLOOR + 0.22, 0.32))
    ball_l = Legs(NEUTRAL.r, (-0.13, FLOOR, -0.08))
    legs = (
        (0, kick_r),
        (0.5, ball_r),
        (1, NEUTRAL),
        (2, kick_r),
        (2.5, ball_r),
        (3, NEUTRAL),
        (4, kick_l),
        (4.5, ball_l),
        (5, NEUTRAL),
        (6, kick_l),
        (6.5, ball_l),
        (7, NEUTRAL),
    )
    arms = (
        (0, Arms(T, DOWN)),
        (1, Arms(BENT, BENT)),
        (2, Arms(T, DOWN)),
        (3, Arms(BENT, BENT)),
        (4, Arms(DOWN, T)),
        (5, Arms(BENT, BENT)),
        (6, Arms(DOWN, T)),
        (7, Arms(BENT, BENT)),
    )
    return Block("kick-ball-change", "KICK BALL CHANGE", legs, arms, bounce=0.045)


def grapevine_brazos():
    arms = _repeat_half(
        ((0, Arms(V_UP, V_UP)), (1, Arms(T, T)), (2, Arms(V_UP, V_UP)), (3, Arms(CLAP, CLAP)))
    )
    return Block("grapevine-brazos", "GRAPEVINE CON BRAZOS", _grapevine_legs(), arms, bounce=0.045)


def step_touch_hombros():
    return Block(
        "step-touch-hombros",
        "STEP TOUCH CON HOMBROS",
        _step_touch_legs(),
        _alternate(Arms(GOAL, GOAL), Arms(ELBOWS_DOWN, ELBOWS_DOWN)),
        bounce=0.05,
    )


STEPS = {
    block().key: block
    for block in (
        marcha,
        step_touch_palmada,
        step_touch_v,
        rodilla_arriba,
        toque_lateral,
        grapevine,
        v_step,
        box_step,
        step_touch_doble,
        two_step,
        kick_ball_change,
        grapevine_brazos,
        step_touch_hombros,
    )
}
