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


def _practice(key, name, description):
    """One step repeated for four 8-count phrases."""
    return RoutineSpec(f"n1-{key}", f"N1 · {name}", description, 1, "BEGINNER", 104, (key,) * 4)


STANDARD_V1 = (
    _practice(
        "marcha",
        "Marcha con brazos",
        "Marcha en el sitio subiendo los brazos en V en un tiempo y bajándolos en el siguiente.",
    ),
    _practice(
        "step-touch-palmada",
        "Step touch con palmada",
        "Paso a un lado, junta el otro pie y da una palmada al frente; "
        "brazos en cruz al dar el paso.",
    ),
    _practice(
        "step-touch-v",
        "Step touch con brazos en V",
        "Paso a un lado con los brazos arriba en V; bájalos al juntar los pies.",
    ),
    _practice(
        "rodilla-arriba",
        "Rodilla arriba",
        "Sube una rodilla bajando los codos a la altura de los hombros; alterna lados.",
    ),
    _practice(
        "toque-lateral",
        "Toque lateral",
        "Toca el suelo a un lado con la punta del pie y abre el brazo de ese lado.",
    ),
    RoutineSpec(
        "n1-primer-baile",
        "Primer baile (Nivel 1)",
        "Coreografía original de 80 tiempos que encadena los cinco pasos del Nivel 1.",
        1,
        "BEGINNER",
        104,
        ("marcha", "step-touch-palmada", "rodilla-arriba", "step-touch-v", "toque-lateral") * 2,
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
