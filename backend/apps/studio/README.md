# Estudio del instructor

API de la sección `/estudio` de la web: el instructor sube sus rutinas,
revisa cómo quedó el video y las publica en sus cursos. Solo instructores y
administradores (`IsInstructorOrAdmin`), y cada uno ve únicamente sus rutinas.

| Endpoint | Función |
| --- | --- |
| `GET/POST /api/studio/routines/` | Listar y subir (multipart, `master_video` obligatorio) |
| `GET/PATCH/DELETE /api/studio/routines/{id}/` | Ver, editar (un video nuevo vuelve a borrador) y borrar |
| `POST /api/studio/routines/{id}/publish/` | Publicar en sus cursos: `{"courses": [...], "music_rights": "OWN"}`; un administrador agrega `"catalog": true/false` |
| `POST /api/studio/routines/{id}/unpublish/` | Volver a borrador (también sale del catálogo) |
| `POST/DELETE /api/studio/routines/{id}/catalog/` | Proponer al catálogo SyncDance / retirar la propuesta o salir del catálogo |
| `PUT /api/studio/routines/{id}/choreography/` | Guardar tempo y pasos: `{"bpm", "first_beat_ms", "steps": [{"name", "start_beat", "counts", "tip"}]}`; `bpm: null` los borra |
| `GET /api/studio/routines/{id}/quality/` | Informe de calidad de la referencia (404 si no está lista) |
| `GET /api/studio/courses/` | Sus cursos, con el número de alumnos |
| `GET /api/studio/courses/{id}/` | El curso y sus rutinas (publicadas o asignadas), con cuántos pasos tiene cada una |
| `GET /api/studio/courses/{id}/map/?routine=&follow_mode=&speed=` | Mapa de dificultad de una rutina (`difficulty-map-v1`) |
| `GET /api/studio/courses/{id}/practices/` | Las 50 prácticas más recientes del curso, con la calificación del instructor y la concordancia |
| `PUT/DELETE /api/studio/practices/{uuid}/rating/` | Calificar de 1 a 5 (`{"rating", "comment"}`) o quitar la calificación |

## Reglas

- **Toda subida es un borrador** con visibilidad «solo en cursos».
- **Catálogo SyncDance:** el instructor propone una rutina ya publicada en sus
  cursos (`catalog_review`: `PENDING`). Un administrador la aprueba desde el
  panel (pasa a `CATALOG` y la ven todos los alumnos) o la rechaza con un
  motivo (`REJECTED`, `catalog_review_note`), y el instructor puede proponerla
  de nuevo. Un video nuevo o retirarla de los cursos la saca del catálogo: para
  volver hay que revisarla otra vez. Las rutinas del catálogo que nunca pasaron
  por revisión (las de administradores) no cambian.
- **Un administrador publica directo en el catálogo** desde el mismo estudio:
  `"catalog": true` al publicar, sin necesidad de cursos. Pasa los mismos
  controles (derechos, referencia lista y calidad), congela compás y pasos, y
  queda `APPROVED` a su nombre, sin entrar en la cola de revisión.
  `"catalog": false` la saca del catálogo (entonces necesita algún curso) y sin
  el campo se queda como está. Un instructor que envía `"catalog": true`
  recibe un 400; con `false` o sin el campo, su catálogo no cambia.
- **El video se revisa al subirlo**, no minutos después en el worker:
  - formato: MP4, MOV, M4V, WEBM o MKV
  - tamaño: hasta 200 MB
  - duración: entre 5 s y 5 min
  - imagen: al menos 360 px de lado

  La duración y la imagen se leen con FFmpeg (`imageio-ffmpeg`). Sin FFmpeg,
  el worker sigue comprobando al procesar.
- **Publicar exige:**
  - declarar los derechos de la música (propia, con licencia o libre), que se
    guardan con la fecha
  - una referencia lista del video actual
  - al menos un 80 % de muestras con una sola persona medible
  - elegir al menos uno de sus cursos, o el catálogo si es administrador
- **Informe de calidad** (`quality-report-v1`): porcentaje de muestras por
  calidad (`SINGLE_PERSON`, `NO_USABLE_POSE`, `MULTIPLE_PEOPLE`) y los tramos
  de 1 s o más sin una sola persona medible. El 80 % y el segundo son
  **provisionales** hasta la validación física (E2). Sin muestras, los
  porcentajes son `null`, nunca 0.
- **Compás y pasos** (`choreography.py`): el instructor marca el tempo
  (60–180 BPM) y dónde cae el primer «1», y divide la rutina en pasos con
  nombre, inicio en tiempos desde ese «1», duración en tiempos (1–32) y un
  consejo breve. Los pasos no se solapan y terminan dentro del video. Se
  guardan como **borrador** en `Routine.choreography`, junto con el video en el
  que se marcaron, y se pueden editar cuando quiera.
- **Publicar congela** el borrador en el `scoring_profile` de la referencia, en
  milisegundos: `beat_grid` (`beat-grid-v1`) y `steps` (`routine-steps-v1`).
  Una versión READY nunca se edita: si cambiaron, se crea otra versión que
  reutiliza los mismos archivos (análisis, video ligero y miniatura), sin
  volver a procesar. `choreography.unpublished_changes` avisa cuando lo
  publicado no coincide con el borrador.
- **Un video nuevo** conserva los pasos (están contados en tiempos) pero pide
  revisar el primer «1»: `choreography.stale` y publicar responde 409 hasta
  guardar de nuevo. La fixture `mobile/test/fixtures/references/scoring_profile_v1.json`
  fija el formato que leen Python y Dart.
- **Video para los alumnos:** el worker prepara una versión de 720p y una
  miniatura (ver `apps/routines/README.md`). `processing.light_video` y
  `processing.poster` dicen si la versión actual las tiene; la web muestra la
  miniatura y reproduce el mismo archivo que descarga el teléfono.
- **Borrar** solo una rutina sin prácticas, tareas ni videos de alumnos; si
  no, se retira de los cursos. Los archivos se borran después de confirmar,
  incluidos la versión para la app y la miniatura.

## Progreso del curso (`progress.py`)

- **Mapa de dificultad:** por cada paso publicado, el último resultado
  comparable de cada alumno y, para el grupo, la mediana, la proporción bajo
  50 (GOOD del juego) y cuántos alumnos tienen evidencia. Comparable es la
  versión que los alumnos descargan hoy, un mismo modo (espejo o mismos lados)
  y una misma velocidad. Un resultado cuenta si el paso se midió al menos en un
  50 %. Sin evidencia es `null` («—»), nunca 0. Las cifras del grupo y los
  **errores frecuentes** (avisos que salieron dentro del paso, por alumnos
  afectados) se muestran solo con 3 alumnos o más. Umbral, cobertura y mínimo
  son **provisionales** hasta la validación física.
- **Calificación del instructor** (`coaching.PracticeRating`): 1 a 5 sobre una
  práctica de un alumno de sus cursos, una por instructor y práctica. El alumno
  no la ve; el comentario opcional se guarda como observación, que sí lee.
- **Concordancia** (`coaching.concordance`): correlación de rangos de Spearman
  entre la calificación y la similitud de la app, solo con prácticas a
  velocidad normal y cobertura ≥ 50 %; sin al menos 5 pares no hay cifra.

Qué ve cada alumno lo decide `apps.routines.selectors.get_routines_for_user`.
