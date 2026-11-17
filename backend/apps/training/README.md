# Sesiones de entrenamiento — contrato de sincronización

Django guarda resúmenes calculados en el teléfono. No recibe frames, poses ni
video, y no recalcula el score.

## `POST /api/training/sessions/`

El móvil envía cada resumen `local-session-v1` congelado:

| Campo | Origen en el móvil | Notas |
|---|---|---|
| `id` | UUID v4 del resumen local | Clave de idempotencia |
| `routine` + `reference_version` | `reference.routine` / `reference.version` | También se acepta `reference` (PK) |
| `started_at`, `finished_at` | UTC con `Z` | `status`: `COMPLETED` |
| `duration_ms`, `evaluated_ms` | `summary` | `duration_ms` debe coincidir con la referencia |
| `pose_score`, `overall_score` | `summary.score` | En `pose-window-v1` el score global es solo de pose |
| `timing_score` | — | `null` hasta validar una métrica temporal |
| `angle_score`, `position_score`, `mean_error_degrees`, `mean_position_error` | `summary` | `null` si `evaluated_ms == 0` |
| `reached_video_end` | `summary` | |
| `follow_mode` | `summary.follow_mode` | `mirror` (espejo) o `same-side`; v1 local = `same-side` |
| `playback_speed` | `summary.playback_speed` | 0.5, 0.75 o 1 (modo aprender); ausente = 1 |
| `scoring_version`, `summary_version`, `feedback_version` | `summary` | Obligatorias con resumen |
| `timeline_segments` | `summary.segments` | Contiguos desde 0, cubren `duration_ms` |
| `feedback_counts` | `summary.feedback` | Avisos mostrados, no todas las desviaciones |
| `game` | `game` (opcional) | Solo partidas del modo juego; ver abajo |
| `step_summary_version` + `step_results` | `summary.steps` (opcional) | Resultados por paso del instructor; ver abajo |
| `calibration` | `calibration` (opcional) | `{"attempts", "calibrated"}`: intentos de encuadre desde la práctica guardada anterior |

El servidor deriva `quality_ratio = evaluated_ms / duration_ms` (cobertura
estimada) y copia `pose_schema_version`, `feature_schema_version` y
`reference_version` desde la referencia.

Se rechaza con 400, sin escribir filas parciales:

- una métrica con valor sin tiempo evaluado, o ausente con tiempo evaluado;
- tramos con huecos, solapes o evidencia que no suma `evaluated_ms`;
- un tramo con score sin evidencia;
- avisos duplicados o avisos sin tiempo evaluado;
- valores no finitos, una referencia que no está `READY` o una rutina no visible.

## Resultados por paso (`step-summary-v1`)

Si la versión de referencia trae pasos del instructor
(`scoring_profile.steps`), el teléfono envía uno por paso, calculado con las
mismas casillas de 100 ms que los tramos:

```json
"step_summary_version": "step-summary-v1",
"step_results": [{"index": 0, "start_ms": 1250, "end_ms": 5536,
                  "evaluated_ms": 3900, "score": 72.4,
                  "feedback": {"leftElbow_extend": 2}}]
```

Se rechaza con 400 si no son exactamente los pasos publicados (cantidad,
orden y ventanas), si un paso tiene score sin evidencia, si la evidencia de
los pasos supera `evaluated_ms`, o si sus avisos no están entre los de la
práctica o los superan. Sin pasos en la referencia, la lista va vacía. Un
teléfono anterior no los envía y la práctica se guarda igual. Es un bloque
aparte de `summary_version`: el progreso del alumno compara por esa versión
y no se reinicia.

## Resultado del modo juego (`game`)

Las prácticas jugadas en modo «Bailar» añaden el `GameSummary` del teléfono:

```json
"game": {"version": "dance-game-v2", "points": 175, "max_points": 400,
         "max_combo": 2,
         "counts": {"perfect": 1, "great": 1, "good": 0, "miss": 1, "unrated": 1}}
```

Se guarda en `GameResult` (1:1 con la sesión). Se rechaza con 400 si
`points` no es 100·perfect + 75·great + 50·good, si `max_points` no es 100 por
movimiento, si `max_combo` supera los movimientos calificados (sin `unrated`),
con una versión desconocida (`dance-game-v1` y `v2`) o sin resumen terminado.
`unrated` son movimientos en que no se vio al alumno: nunca cuentan como MISS.
La respuesta añade `stars` (0–5), calculado aquí con los mismos umbrales que el
teléfono (30/45/60/75/90 % de los puntos). Sin partida, `game` es `null`.

## Historial en otro teléfono

`GET /api/training/sessions/` añade, solo lectura, `routine_name` y
`reference_metadata` (el mismo formato de `GET /routines/{id}/reference/`). Con
eso el teléfono reconstruye su historial local (**Traer prácticas del
servidor** en el historial) pasando cada registro por las mismas reglas que un
resumen local; los que no las cumplen (formatos anteriores) se omiten.

## Vista del instructor (Django Admin)

Con un usuario staff (en desarrollo, la semilla `admin` / `admin`) o con el rol
Instructor, que ve solo a los alumnos de sus cursos (ver `apps/coaching/README.md`):

- **Sesiones de baile:** alumno, rutina, modo (Juego o Práctica), estrellas,
  puntos, similitud y cobertura; filtros por modo, rutina, espejo y velocidad,
  búsqueda por alumno o rutina y navegación por fecha. Solo lectura, salvo las
  **observaciones del instructor** que se añaden al pie de cada práctica.
- **Progreso por alumno** (`/admin/training/dancesession/progreso/`): por alumno
  y rutina, prácticas, partidas, mejor similitud (velocidad normal y cobertura
  ≥ 50 %, el mismo corte provisional del teléfono), mejores estrellas y última
  práctica (`get_student_progress` en `selectors.py`). «—» es sin evidencia,
  nunca cero. **Descargar CSV (Excel)** exporta la misma tabla (`;`, UTF-8 con
  BOM, hora local); un nombre que empieza con `= + - @` se exporta como texto
  para que la hoja de cálculo no lo ejecute como fórmula.

## Reintentos

| Situación | Respuesta | Qué hace el cliente |
|---|---|---|
| Sesión nueva válida | 201 | Marcar sincronizada |
| Mismo UUID, mismo alumno | 200 con la copia guardada | Marcar sincronizada |
| Mismo UUID de otra cuenta | 409 | No reintentar |
| Datos inválidos o rutina ya no disponible | 400 | No reintentar; conservar local |
| Red, 5xx, 401 | — | Reintentar más tarde |

El reintento del mismo alumno se comprueba antes de validar. Así una respuesta
perdida no bloquea la cola aunque la rutina se haya desactivado después.
Los resúmenes son inmutables: un reintento nunca reescribe la copia guardada.

`segment_scores` (por zona corporal) y `error_events` (con tiempos) siguen
disponibles para una fase posterior; el móvil actual no los produce.

## Validación

`apps/training/tests/`: contrato completo, nulls frente a cero real, reintento
idempotente tras desactivar la rutina, conflicto entre cuentas e invariantes
rechazadas sin filas parciales. Las fixtures `upload_v1.json` y
`upload_game_v1.json` las genera el teléfono (`session_sync_test.dart`).
