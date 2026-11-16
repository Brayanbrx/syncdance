# Cursos (Fase 8: instructor y asignaciones)

Relación instructor–alumno sin Angular: el instructor trabaja en el Django
Admin y el alumno en la app (**Inicio → Mis cursos**).

## Modelo

| Modelo | Qué guarda |
| --- | --- |
| `Course` | Nombre, instructor, código para unirse (8 caracteres sin 0/O/1/I/L) y si acepta alumnos nuevos |
| `Enrollment` | Alumno inscrito en un curso (único por curso y alumno) |
| `Assignment` | Rutina asignada al curso, objetivo en estrellas (1–5, por defecto 3), fecha límite e indicaciones; una por rutina y curso |
| `SessionNote` | Observación del instructor sobre una práctica sincronizada; el alumno la lee en la app |

Una tarea se **cumple** con las mejores estrellas del modo juego a velocidad
normal (`playback_speed = 1.0`) en esa rutina, con cualquier partida ya
sincronizada (también las anteriores a la tarea). El modo aprender es más lento
y no cuenta. Sin partidas, las estrellas son `null`, nunca cero. Una tarea
**vencida** no está cumplida y su fecha límite ya pasó.

## Roles en el Admin

- El rol **Instructor** o **Administrador** marca `is_staff` al guardar el
  usuario: no hace falta tildar «Es staff» ni asignar permisos de modelo.
- Un instructor ve y edita **solo sus cursos**; al crear uno queda como su
  instructor. En **Sesiones de baile** y **Progreso por alumno** (y su CSV) ve
  solo a los alumnos de sus cursos, sin poder borrar sesiones.
- En cada práctica puede escribir una **observación** (no se edita después).
- **Progreso del curso** (`/admin/coaching/course/<id>/progreso/`): una fila por
  alumno con las estrellas de cada tarea, ✓ si cumple y «vencida» si no.
- Acción **Generar un código nuevo**: el anterior deja de servir; los inscritos
  siguen en el curso. Desmarcar «acepta alumnos nuevos» cierra las inscripciones.
- Superusuarios y el rol Administrador ven todos los cursos y alumnos.

## API (alumno, JWT)

| Endpoint | Función |
| --- | --- |
| `GET /api/coaching/courses/` | Cursos del alumno con tareas y su progreso (`best_stars`, `practices`, `last_practice_at`, `completed`, `overdue`) |
| `POST /api/coaching/courses/join/` | `{"code": "abcd-2345"}`: ignora mayúsculas, espacios y guiones. 201 nuevo, 200 si ya estaba, 404 código no válido o curso cerrado |
| `POST /api/coaching/courses/{id}/leave/` | Salir del curso (204); 404 si no pertenece |
| `GET /api/coaching/notes/` | Observaciones sobre las prácticas propias, la más reciente primero |

Unirse admite 20 intentos por hora por cuenta (`join` en
`DEFAULT_THROTTLE_RATES`) para que los códigos no se adivinen; leer el progreso
no se limita.

## Pruebas

`pytest apps/coaching`: unirse (normalización, idempotencia, cerrado, límite),
progreso por tarea (sin evidencia, modo aprender, cumplida, vencida), salir,
observaciones privadas y el alcance del instructor en el Admin.
