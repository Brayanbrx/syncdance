# Estudio del instructor

API de la sección `/estudio` de la web: el instructor sube sus rutinas,
revisa cómo quedó el video y las publica en sus cursos. Solo instructores y
administradores (`IsInstructorOrAdmin`), y cada uno ve únicamente sus rutinas.

| Endpoint | Función |
| --- | --- |
| `GET/POST /api/studio/routines/` | Listar y subir (multipart, `master_video` obligatorio) |
| `GET/PATCH/DELETE /api/studio/routines/{id}/` | Ver, editar (un video nuevo vuelve a borrador) y borrar |
| `POST /api/studio/routines/{id}/publish/` | Publicar en sus cursos: `{"courses": [...], "music_rights": "OWN"}` |
| `POST /api/studio/routines/{id}/unpublish/` | Volver a borrador |
| `GET /api/studio/routines/{id}/quality/` | Informe de calidad de la referencia (404 si no está lista) |
| `GET /api/studio/courses/` | Sus cursos, con el número de alumnos |

## Reglas

- **Toda subida es un borrador** con visibilidad «solo en cursos». Solo un
  administrador la lleva al catálogo SyncDance; esa es la revisión.
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
  - elegir al menos uno de sus cursos
- **Informe de calidad** (`quality-report-v1`): porcentaje de muestras por
  calidad (`SINGLE_PERSON`, `NO_USABLE_POSE`, `MULTIPLE_PEOPLE`) y los tramos
  de 1 s o más sin una sola persona medible. El 80 % y el segundo son
  **provisionales** hasta la validación física (E2). Sin muestras, los
  porcentajes son `null`, nunca 0.
- **Video para los alumnos:** el worker prepara una versión de 720p y una
  miniatura (ver `apps/routines/README.md`). `processing.light_video` y
  `processing.poster` dicen si la versión actual las tiene; la web muestra la
  miniatura y reproduce el mismo archivo que descarga el teléfono.
- **Borrar** solo una rutina sin prácticas, tareas ni videos de alumnos; si
  no, se retira de los cursos. Los archivos se borran después de confirmar,
  incluidos la versión para la app y la miniatura.

Qué ve cada alumno lo decide `apps.routines.selectors.get_routines_for_user`.
