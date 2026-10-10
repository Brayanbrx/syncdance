---
name: syncdance-pose
description: Reglas del dominio de pose de SyncDance AI. Usar SIEMPRE antes de crear, modificar, revisar o testear código de pose, landmarks, normalización corporal, ángulos, quality gate, calibración, comparación/matching con la referencia, scoring, feedback live, resumen de sesión o el formato de referencia motion-features-v1, tanto en Flutter (mobile/lib/features/training, mobile/lib/features/routines/reference) como en Python (backend/ai_engine, backend/apps/routines). Triggers - pose, PoseFrame, PoseEstimator, ML Kit, MediaPipe, landmark, joint, normalización, ángulo, score, similitud, feedback, cue, referencia, maestro, calibración, encuadre, espejo, izquierda/derecha.
---

# SyncDance — dominio de pose

SyncDance compara en el teléfono la pose del alumno con una referencia
precalculada del maestro y da feedback inmediato. Esta skill fija las reglas que
el código ya cumple. **El código es la fuente de verdad de los valores**; aquí se
describen invariantes y dónde viven. Leer el archivo antes de cambiarlo.

## Mapa del pipeline

```text
LIVE (solo Flutter, sin red):
cámara -> PoseEstimator -> PoseFrame -> PoseQualityGate/calibración
       -> LivePractice: PoseNormalizer -> BodyFeatureExtractor -> PoseMatcher
          (ventana) -> FeedbackRules -> LiveFeedback -> SessionAccumulator
       -> historial local -> SessionSync (fuera del loop, cola offline) -> Django

OFFLINE (Django + Celery):
video maestro -> FFmpeg 12 fps -> MediaPipe -> features/body.py
       -> reference_motion (motion-features-v1, gzip) -> descarga y validación en Flutter
```

| Etapa | Flutter (`mobile/lib/features/`) | Python (`backend/`) |
|---|---|---|
| Contrato y modelo | `training/pose/pose_estimator.dart`, `pose_frame.dart` | — |
| Adaptador de motor | `training/pose/adapters/mlkit_*` | `ai_engine/pose/reference.py` |
| Quality gate, calibración, suavizado | `training/pose/pose_measurements.dart` | — |
| Normalización y ángulos | `training/pose/body_features.dart` | `ai_engine/features/body.py` |
| Referencia | `routines/reference/motion_reference.dart`, `reference_cache.dart` | `ai_engine/pose/reference.py`, `apps/routines/tasks.py` |
| Reloj video↔captura | `training/comparison/capture_video_clock.dart` | — |
| Loop live (sin widgets) | `training/comparison/live_practice.dart` | — |
| Matching y score | `training/comparison/angle_matcher.dart`, `pose_matcher.dart` | `ai_engine/alignment/`, `ai_engine/scoring/` (offline) |
| Feedback | `training/feedback/feedback_rules.dart`, `live_feedback.dart` | — |
| Resumen e historial | `training/comparison/session_summary.dart`, `training/history/` | `apps/training/` |
| Sincronización y progreso | `training/history/session_sync.dart`, `routine_progress.dart` | `apps/training/` (contrato en su README) |
| Modo juego | `training/game/dance_game.dart`, `presentation/dance_game_screen.dart` | — (bloque `game` solo local) |

## Invariantes (no negociables)

### Arquitectura
1. **El loop live no llama a Django.** Ningún frame, landmark ni score por frame
   sale del teléfono; Redis/Celery no participan. Tras descargar la rutina, el
   entrenamiento funciona sin Internet.
2. **El dominio no conoce el SDK.** Los tipos de ML Kit/MediaPipe solo existen en
   `pose/adapters/`. El resto trabaja con `PoseFrame`, `Joint` y `BodyAngle`.
3. Contrato de `PoseEstimator`: una inferencia a la vez, descartar frames viejos,
   reportar errores por el stream, liberar cámara y detector en `stop()` y al ir a
   background, y `stop()` repetido seguro.
4. `ai_engine` no importa Django. `cv2`/`mediapipe` se importan de forma diferida y
   solo en el worker. Monolito modular: sin microservicios, WebSockets para pose ni
   frames guardados como filas de PostgreSQL.

### Coordenadas (`pose-v1`)
5. Imagen derecha (upright), x hacia la derecha, **y hacia abajo**, normalizadas por
   ancho/alto. Valores fuera de [0, 1] = joint fuera del encuadre; se permiten.
6. **Multiplicar x por `imageAspectRatio` antes de cualquier distancia o ángulo.**
7. Timestamps en ms monótonos desde el inicio de captura, no UTC. Timestamps
   duplicados o desordenados se ignoran: no avanzan filtros ni calibración.
8. `z` queda ausente hasta validar su escala entre motores.

### Lados y espejo
9. **Izquierda/derecha son anatómicas y nunca se intercambian en el alumno.** El
   espejo de la cámara frontal es solo una transformación de dibujo en el overlay.
   Convención visual: izquierda anatómica naranja, derecha celeste.
   El **modo espejo** (`FollowMode.mirror`, por defecto) refleja la *referencia del
   maestro* de forma explícita (`mirrorReference`: swap de lados + x → −x) para que
   el alumno lo siga como en un espejo. Es una transformación de la coreografía,
   versionada en `follow_mode`, nunca una corrección de la preview.

### Ausente ≠ cero
10. Un joint no detectado **no está** en la lista; un ángulo no calculable **no está**
    en el mapa; una métrica sin evidencia es `null` (UI: `—`). Nunca rellenar con 0,
    nunca penalizar un dato ausente como error máximo y nunca promediar sobre huecos.
11. Validar `isFinite` en toda entrada numérica; los constructores lanzan
    `ArgumentError` ante NaN/Infinity o confianza fuera de [0, 1].

### Normalización y features
12. `body-normalized-v1`: origen = punto medio de caderas; escala = distancia del
    punto medio de caderas al punto medio de hombros. Se usan solo landmarks con
    confianza ≥ 0.5 y dentro de [0, 1]. Sin esos cuatro anclajes no hay pose
    normalizada. No se rota: la inclinación del torso es información.
13. `body-features-v1`: seis ángulos 2D sin signo en [0, 180] (codos, hombros y
    rodillas por lado), definidos por tripletas en `_triplets` / `TRIPLETS`.
14. **Paridad Dart ↔ Python.** `body_features.dart` y `ai_engine/features/body.py`
    deben producir lo mismo. La fixture compartida
    `mobile/test/fixtures/poses/body_angles_v1.json` se prueba en ambos lados.
    Un cambio en uno exige el mismo cambio en el otro, en el mismo commit.

### Calidad antes de puntuar
15. Sin `PoseQuality.ready` y calibración completa no se mide ni se puntúa. Un
    tramo de mala calidad queda **no evaluable**; no baja el score. La UI explica
    cómo corregir el encuadre.
16. Cambiar de orientación o de aspect ratio, o un hueco > 500 ms, reinicia el
    procesador. Al pausar, hacer seek o perder calidad se invalidan el reloj y el
    feedback.

### Referencia (`motion-features-v1`)
17. 12 muestras/s, `timeline: video-start-cfr-v1`, `smoothing: none` y máximo 5 min.
    Cada frame lleva `quality`: `SINGLE_PERSON`, `NO_USABLE_POSE` o `MULTIPLE_PEOPLE`.
    Solo se compara contra `SINGLE_PERSON`.
18. Artefacto determinista: JSON con `sort_keys`, `allow_nan=False` y gzip con
    `mtime=0`. Incluye procedencia (`engine`, `model_sha256`, `source_sha256`).
19. Flutter verifica el SHA-256 **sobre los bytes gzip, antes de descomprimir**,
    aplica límites de tamaño comprimido/expandido y exige todas las cadenas de
    versión. Una descarga fallida nunca borra la versión anterior. La caché va
    separada por cuenta y servidor.

### Matching y score
20. Sincronización live = posición actual del video maestro ± una ventana pequeña
    (`AngleMatcher.windowMs`). **Nunca cruzar** una muestra incompleta o ambigua
    para encontrar un match conveniente. DTW completo solo offline (`ai_engine/alignment/`).
21. El error angular y el posicional se miden contra **la misma** muestra. Empates:
    se elige el menor |offset|, de forma determinista.
22. Score en 0–100, explicable a partir de ángulos, distancias normalizadas,
    timing y pesos. **Nunca un LLM** en el score ni en el loop. Misma entrada →
    mismo resultado.
23. Pesos y umbrales actuales son **provisionales** (componentes al 50 %, corte en
    1 torso, 90°). Documentarlos como experimentales hasta la validación física.

### Feedback live
24. Solo reglas geométricas rápidas. Son sugerencias respecto al maestro, no
    diagnósticos. Mensajes en español, accionables, de un solo tema.
25. Anti-ruido: un único cue visible; exige umbral, persistencia en tiempo **y** en
    número de muestras, cooldown por región e histéresis. Ver constantes en
    `LiveFeedback`. Nunca un mensaje distinto en cada frame.
26. Los cues resaltan las articulaciones implicadas (`highlightedJoints`).

### Resumen
27. Bins de 100 ms de video; el primer resultado válido gana. La cobertura es
    estimada, no observación continua. Segmentos sin evidencia → `score: null`.
    El resumen guarda `scoringVersion`, `summaryVersion` y `feedbackVersion`.

## Versionado

Cualquier cambio de comportamiento, umbral o fórmula **sube la versión** de su
componente. Así los historiales guardados siguen siendo interpretables.

| Cadena | Dónde |
|---|---|
| `pose-v1` | `PoseFrame.schemaVersion` |
| `body-normalized-v1` | `NormalizedPose.schemaVersion` |
| `body-features-v1` | `BodyFeatures.schemaVersion` |
| `pose-measurements-v2` | `PoseMeasurementProcessor.version` (v2: encuadre antes que confianza) |
| `angle-window-v1` | `AngleMatcher.version` |
| `pose-window-v1` | `PoseMatcher.version` (= `scoringVersion`) |
| `geometric-feedback-v2` | `FeedbackRules.version` |
| `pose-summary-v1` | `SessionAccumulator.version` |
| `local-session-v2` (lee v1), `session-sync-v1` | `SavedSession.toJson`, marcadores de `SessionStore` |
| `follow_mode`: `mirror` / `same-side` | `FollowMode` en `comparison/follow_mode.dart`; resumen, subida y base del progreso |
| `playback_speed`: 0.5 / 0.75 / 1 | `SessionAccumulator.speeds`; modo aprender, resumen, subida y base del progreso |
| `syncdance-choreo-v1`, `estandar-v1` | `ai_engine/choreography/curriculum.py`: coreografías generadas (referencia exacta, sin MediaPipe) |
| `routine-progress-v1` | `RoutineProgressCalculator.version` (cobertura mínima provisional) |
| `dance-game-v1` | `DanceGame.version`: movimientos de 1 s, umbrales PERFECT/GREAT/GOOD, estrellas (provisionales) |
| `motion-features-v1`, `reference-body-v1`, `video-start-cfr-v1` | `ai_engine/pose/reference.py` **y** la validación de `motion_reference.dart` |

Cambiar el formato de la referencia toca a la vez el generador Python, el
validador Dart, el serializer/modelo de `RoutineReference` y las fixtures de
`mobile/test/fixtures/references/`.

Cambiar el resumen subido toca `SavedSession.toUpload()`, el serializer de
`DanceSession` y la fixture compartida `mobile/test/fixtures/sessions/upload_v1.json`
(Dart la compara; Django la publica y espera 201).

## Flujo de trabajo para un cambio

1. Leer el README de la carpeta afectada (`training/README.md`,
   `comparison/README.md`, `feedback/README.md`, `apps/routines/README.md`).
2. Escribir primero el test con fixtures sintéticas: casos de joints ausentes,
   valores no finitos, timestamps desordenados, empates, ventana vacía y lado
   anatómico con espejo. Las funciones de dominio son Dart/Python puro y se prueban
   sin teléfono.
3. Si toca geometría, actualizar la fixture compartida y probar en ambos lados.
4. Subir la versión correspondiente si cambia el resultado.
5. Registrar el paso en el README de la feature: qué se logró, validación
   automatizada, **prueba física manual pendiente** y límites. Ser honesto: las
   fixtures sintéticas no certifican la precisión de un motor; las imágenes/s de
   captura no son FPS de inferencia.
6. Verificar con lo mismo que ejecuta CI (`.github/workflows/ci.yml`):

```powershell
# mobile/
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

# backend/  (DJANGO_SETTINGS_MODULE=config.settings.test)
ruff check .
python manage.py check
python manage.py makemigrations --check --dry-run
pytest
```

## Antipatrones a rechazar

- Importar `google_mlkit_*` o `mediapipe` fuera de los adaptadores.
- Intercambiar left/right del alumno para "corregir" el espejo (el modo espejo
  refleja la referencia del maestro, no al alumno).
- Comparar o promediar prácticas con distinto `follow_mode` o `playback_speed`.
- Procesar con MediaPipe una rutina con `generator`: su referencia sale de la
  coreografía (`generate_standard_catalog`).
- `?? 0` o `0.0` como valor por defecto de un landmark, ángulo o score.
- Calcular distancias con x sin corregir por aspect ratio.
- Puntuar frames que no pasaron el quality gate, o bajar el score por mala calidad.
- Buscar el mejor match saltando huecos de la referencia o fuera de la ventana.
- Enviar frames o landmarks al backend, o usar WebSockets/Celery en el loop live.
- Sincronizar o llamar a la red desde `LivePractice` o durante la práctica.
- Meter lógica de juego (puntos, combo, estrellas) en el scorer: el juego solo
  consume `SessionAccumulator`. Un movimiento sin evidencia es «sin medir», no MISS.
- Cambiar un umbral sin subir la versión, o presentar un umbral como validado.
- Modificar `body_features.dart` sin `features/body.py` (o al revés).
- Errores públicos con rutas del sistema de archivos o logs nativos (`ReferenceError`).
