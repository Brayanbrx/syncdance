# Análisis de canto (servidor)

La práctica de canto en vivo ocurre en el teléfono, sin red, igual que la del
baile (Fase 9 del plan maestro). El servidor solo:

1. convierte la voz sola del instructor en una **referencia de melodía**
   (`pitch-reference-v1`), una vez, en el worker
2. opcionalmente, compara una grabación del alumno con esa referencia
   **después** de practicar

No importa Django. librosa y FFmpeg se cargan de forma diferida y solo en los
workers (`requirements-voice.txt`).

## Origen

Se adaptó del microservicio aparte `singing-service` v0.4.0. Se conservó la
extracción de tono con pyin; se reescribió la calificación y se descartó la
capa HTTP (FastAPI, almacén en memoria, colas y reintentos), porque Django y
Celery ya cumplen ese papel.

Mismos audios sintéticos, antes y después:

| Caso | singing-service | Ahora |
|---|---|---|
| Escala afinada, sin referencia | 24/100 («osciló ±400 cents») | 100 |
| Una nota un semitono arriba | 100 % de afinación | 87 %, marca F4 → F#4 |
| La melodía una octava abajo | 0 % | 100 %, avisa «octava −1» |
| Una sola nota sobre toda la escala | 35 % | 13 % de afinación, 13 de nota general |
| Empezar 0,4 s tarde | ritmo 97, sin aviso | afinación 100, entrada 0 %, aviso `LATE` |

## Módulos

| Archivo | Qué hace |
|---|---|
| `audio.py` | Cualquier audio o video → muestras mono de 16 kHz con FFmpeg. Sin protocolos remotos ni playlists; máximo 10 min |
| `pitch.py` | Muestras → un tono cada 32 ms (pyin). Sin voz = `NaN`, nunca 0 |
| `notes.py` | Tono → notas cantadas (Viterbi por semitonos con costo de cambio) |
| `evaluate.py` | Puntajes contra una referencia (`compare`) o de la voz sola (`evaluate_solo`) |
| `reference.py` | Artefacto `pitch-reference-v1`: determinista, gzip con `mtime=0`, validado al leer |
| `__main__.py` | Herramienta para probar con grabaciones reales |

## Versiones

| Cadena | Dónde | Cambia si… |
|---|---|---|
| `voice-pitch-v1` | `pitch.ALGORITHM_VERSION` | parámetros de pyin o el umbral de silencio |
| `voice-notes-v1` | `notes.ALGORITHM_VERSION` | la segmentación en notas |
| `pitch-reference-v1` | `reference.SCHEMA_VERSION` | el formato del artefacto |
| `voice-score-v1` | `evaluate.SCORE_VERSION` | cualquier umbral o fórmula de puntaje |

## Cómo se califica contra una referencia

- **Nada se estira.** Se busca un único desfase global (±1 s) a partir de
  cuándo suena la voz y cuándo descansa, nunca de las notas. Después, cada
  nota se juzga donde se cantó. El DTW libre del servicio anterior dejaba que
  una nota equivocada «tomara prestados» cuadros de su vecina.
- **La octava no es un error.** Se elige una sola octava para toda la
  grabación, y solo si al menos reduce a la mitad la distancia a la melodía.
  La transposición por semitonos solo se aplica si la elige el alumno
  (`transpose_semitones`): adivinarla escondería a quien canta un semitono
  abajo todo el tiempo.
- **Cada nota cuenta por su centro.** Se toma el centro del tono del alumno
  en el 60 % central de la nota, sin ataque ni final. Dentro de 50 cents, está
  afinada.
- **Entrada a tiempo:** cuándo el alumno llega afinado a la nota, contra el
  inicio en la pista (la grabación arranca con la pista, como en la app). Una
  nota que repite la anterior no se cronometra.
- **Ausente ≠ cero.** Una nota no cantada baja la cobertura, nunca la
  afinación. Un puntaje sin evidencia es `None`.

**General** = afinación × (1 − 0,4 × lo que falte en entrada, estabilidad y
volumen) × cobertura. La afinación manda: el resto solo puede restarle hasta
un 40 %.

**Sin referencia** (calentamiento), cada nota se compara con el semitono más
cercano, una vez quitado el desfase global de afinación de quien canta. El
margen es de 25 cents, porque ninguna nota está a más de 50 de un semitono.

Los avisos (`findings()`) son códigos estables: `OUT_OF_TUNE`, `OCTAVE_SHIFT`,
`MISSED_NOTES`, `LATE` y `EARLY`. Los textos los escribe la app.

## Umbrales provisionales

Todos son provisionales hasta validarlos con cantantes y profesores reales, y
viajan con `voice-score-v1`:

- 50 cents con referencia y 25 sin ella
- 150 ms de tolerancia de entrada
- penalización de cambio de nota de 2 semitonos (mantiene un vibrato de hasta
  ±80 cents a 4,5–5,5 Hz y sigue encontrando notas de 128 ms)
- ±1 s de desfase máximo
- 40 % de peso para lo que no es afinación
- aviso `NOT_VOICE_ONLY` si la confianza mediana de pyin baja de 0,5 (voz
  limpia sintética: 0,985; con acordes de fondo: 0,28 o menos)

## Probar con grabaciones reales

```powershell
docker compose exec backend python -m ai_engine.voice /app/media/alumno.m4a
docker compose exec backend python -m ai_engine.voice /app/media/alumno.m4a --referencia /app/media/profe.m4a
# --transponer -2, --sin-octava, --json
```

## Validación

- **Automatizada:** `ai_engine/tests/test_voice.py`.
  - Pistas construidas a mano: vibrato hasta ±60 cents, deslizamientos,
    consonantes, saltos de octava de pyin, notas rápidas.
  - Pyin y FFmpeg con voces sintéticas, incluidos los casos en que fallaba el
    servicio anterior.
  - Artefacto determinista, artefactos dañados y la playlist trampa.
- **Prueba física pendiente:**
  - grabaciones reales de instructores (voz sola) y alumnos, en teléfonos
    reales
  - calibrar umbrales y pesos contra la nota de un profesor de canto
  - confirmar el aviso de música de fondo con canciones reales

## Límites

- **Una sola voz:** con música de fondo, el tono sigue a los instrumentos. Se
  exige la voz sola del instructor.
- **Vibrato muy ancho y rápido:** un vibrato de más de ±80 cents a 6,5 Hz o más
  puede partir una nota.
- **Ritmo:** se mide solo por la entrada a cada nota, no por su duración.
- **Grabaciones largas:** máximo 10 minutos por grabación.
