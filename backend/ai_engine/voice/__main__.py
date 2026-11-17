"""Try the singing analysis on real recordings, before any screen exists.

    python -m ai_engine.voice alumno.m4a
    python -m ai_engine.voice alumno.m4a --referencia profe.m4a [--transponer -2]
    python -m ai_engine.voice alumno.m4a --referencia profe.m4a --json

Inside the development containers:

    docker compose exec backend python -m ai_engine.voice /app/media/prueba.m4a
"""

import argparse
import json
import sys

from ai_engine.voice import VoiceError
from ai_engine.voice.audio import decode
from ai_engine.voice.evaluate import compare, evaluate_solo
from ai_engine.voice.pitch import track_from_samples
from ai_engine.voice.reference import build_pitch_reference

LABELS = {
    "overall": "General",
    "tuning": "Afinación",
    "timing": "Entrada a tiempo",
    "stability": "Estabilidad",
    "volume": "Volumen parejo",
    "coverage": "Notas cantadas",
}


def main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m ai_engine.voice")
    parser.add_argument("grabacion", help="audio o video de quien canta")
    parser.add_argument("--referencia", help="voz sola del instructor")
    parser.add_argument("--transponer", type=int, default=0, help="semitonos elegidos")
    parser.add_argument("--sin-octava", action="store_true", help="no perdonar la octava")
    parser.add_argument("--json", action="store_true", help="resultado completo en JSON")
    args = parser.parse_args(argv)

    try:
        student = track_from_samples(decode(args.grabacion))
        if args.referencia:
            reference = build_pitch_reference(args.referencia)
            result = compare(
                student,
                reference.track,
                reference.notes,
                transpose_semitones=args.transponer,
                allow_octave=not args.sin_octava,
            )
        else:
            reference = None
            result = evaluate_solo(student)
    except VoiceError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    data = result.to_dict()
    if reference is not None:
        data["reference_quality"] = reference.metadata["quality"]
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return 0

    for key, label in LABELS.items():
        value = data["scores"][key]
        print(f"{label:<18} {'—' if value is None else value}")
    if reference is not None:
        print(f"Desfase           {data['offset_ms']} ms, octava {data['octave_shift']:+d}")
        for warning in reference.metadata["quality"]["warnings"]:
            print(f"Aviso referencia  {warning}")
    print()
    for note in data["notes"]:
        expected = note["expected"]
        sung = note["sung"] or "—"
        cents = "" if note["cents"] is None else f"{note['cents']:+.0f} cents"
        onset = "" if note["onset_error_ms"] is None else f"entrada {note['onset_error_ms']:+d} ms"
        start = f"{expected['start_ms'] / 1000:7.2f}s"
        print(f"{start}  {expected['name']:<4} {sung:<4} {cents:<11} {onset}")
    for item in data["findings"]:
        print("·", json.dumps(item, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
