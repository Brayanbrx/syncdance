"""SyncDance standard v1: basic steps by level and original combos.

The step vocabulary (march, step touch, knee lift, side tap...) is the common
language of dance-fitness classes; the combos here are original. Every routine
faces the camera for its whole length so the phone can rate it.
"""

import dataclasses
import hashlib
import json
from dataclasses import dataclass

from .steps import STEPS, intro
from .timeline import Timeline

GENERATOR_VERSION = "syncdance-choreo-v1"
CURRICULUM_VERSION = "estandar-v1"


@dataclass(frozen=True)
class RoutineSpec:
    key: str
    name: str
    description: str
    level: int
    difficulty: str
    bpm: int
    steps: tuple[str, ...]  # block keys, each one 8 counts

    @property
    def style(self):
        return f"Estándar N{self.level}"

    def blocks(self):
        return [intro()] + [STEPS[key]() for key in self.steps]

    def timeline(self):
        return Timeline(self.blocks(), self.bpm)


LEVELS = {
    1: ("BEGINNER", 104),  # fundamentals
    2: ("INTERMEDIATE", 112),  # travelling and footwork
    3: ("ADVANCED", 118),  # urban rhythm
}


def _practice(level, key, name, description):
    """One step repeated for four 8-count phrases."""
    difficulty, bpm = LEVELS[level]
    return RoutineSpec(
        f"n{level}-{key}", f"N{level} · {name}", description, level, difficulty, bpm, (key,) * 4
    )


def _combo(level, key, name, description, steps):
    difficulty, bpm = LEVELS[level]
    return RoutineSpec(f"n{level}-{key}", name, description, level, difficulty, bpm, steps * 2)


STANDARD_V1 = (
    _practice(
        1,
        "marcha",
        "Marcha con brazos",
        "Marcha en el sitio subiendo los brazos en V en un tiempo y bajándolos en el siguiente.",
    ),
    _practice(
        1,
        "step-touch-palmada",
        "Step touch con palmada",
        "Paso a un lado, junta el otro pie y da una palmada al frente; "
        "brazos en cruz al dar el paso.",
    ),
    _practice(
        1,
        "step-touch-v",
        "Step touch con brazos en V",
        "Paso a un lado con los brazos arriba en V; bájalos al juntar los pies.",
    ),
    _practice(
        1,
        "rodilla-arriba",
        "Rodilla arriba",
        "Sube una rodilla bajando los codos a la altura de los hombros; alterna lados.",
    ),
    _practice(
        1,
        "toque-lateral",
        "Toque lateral",
        "Toca el suelo a un lado con la punta del pie y abre el brazo de ese lado.",
    ),
    _combo(
        1,
        "primer-baile",
        "Primer baile (Nivel 1)",
        "Coreografía original de 80 tiempos que encadena los cinco pasos del Nivel 1.",
        ("marcha", "step-touch-palmada", "rodilla-arriba", "step-touch-v", "toque-lateral"),
    ),
    _practice(
        2,
        "grapevine",
        "Grapevine (vid)",
        "Paso al lado, cruza por detrás, paso al lado y toca; vuelve hacia el otro lado.",
    ),
    _practice(
        2,
        "v-step",
        "V-step",
        "Abre los pies hacia delante en forma de V y vuelve al centro; "
        "los brazos siguen a los pies.",
    ),
    _practice(
        2,
        "box-step",
        "Box step",
        "Cruza por delante, paso atrás, paso al lado y junta: dibuja un cuadrado en el suelo.",
    ),
    _practice(
        2,
        "step-touch-doble",
        "Step touch doble",
        "Dos step touch hacia un lado y dos hacia el otro, con brazos arriba y palmada.",
    ),
    _combo(
        2,
        "vid-y-v",
        "Vid y V (Nivel 2)",
        "Coreografía original de 64 tiempos con grapevine, V-step, box step y step touch doble.",
        ("grapevine", "v-step", "box-step", "step-touch-doble"),
    ),
    _practice(
        3,
        "two-step",
        "Two-step con rebote",
        "El paso base del hip hop: de lado a lado con rebote y brazos que acompañan.",
    ),
    _practice(
        3,
        "kick-ball-change",
        "Kick ball change",
        "Patada al frente, apoyo rápido atrás con la punta y cambio de peso en el sitio.",
    ),
    _practice(
        3,
        "grapevine-brazos",
        "Grapevine con brazos",
        "Grapevine con brazos arriba en los pasos, en cruz al cruzar y palmada al tocar.",
    ),
    _practice(
        3,
        "step-touch-hombros",
        "Step touch con hombros",
        "Step touch con rebote marcando el ritmo con codos y hombros.",
    ),
    _combo(
        3,
        "urbano-basico",
        "Urbano básico (Nivel 3)",
        "Coreografía original de 64 tiempos con two-step, kick ball change, grapevine "
        "con brazos y step touch con hombros.",
        ("two-step", "kick-ball-change", "grapevine-brazos", "step-touch-hombros"),
    ),
)


def spec_digest(spec):
    """Pins the exact geometry and timing a reference was generated from."""
    payload = {
        "generator": GENERATOR_VERSION,
        "curriculum": CURRICULUM_VERSION,
        "spec": dataclasses.asdict(spec),
        "blocks": [dataclasses.asdict(block) for block in spec.blocks()],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(encoded.encode()).hexdigest()
