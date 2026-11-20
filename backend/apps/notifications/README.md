# Notificaciones

Bandeja de avisos de cada cuenta y notificaciones push por Firebase Cloud
Messaging (FCM). La bandeja funciona aunque no haya push: el móvil la muestra
en **Inicio → campana**.

## Modelo

| Modelo | Qué guarda |
| --- | --- |
| `Notification` | Un aviso para una persona: tipo, título, texto, pantalla del móvil que abre (`route`), leído y enviado por push |
| `PushDevice` | El token FCM de un teléfono, de la cuenta con la sesión abierta en él |

`dedupe_key` impide avisar dos veces del mismo evento a la misma persona: las
señales y la revisión periódica pueden ejecutarse más de una vez.

## Qué se avisa

| Evento | A quién | Cómo se detecta |
| --- | --- | --- |
| Nueva tarea | Alumnos del curso | `post_save` de `Assignment` |
| Tarea vence mañana | Alumnos que aún no cumplen la meta | Celery Beat cada hora (`remind_due_assignments`) |
| Observación del instructor | El alumno de la práctica | `post_save` de `SessionNote` |
| Un alumno cumplió una tarea | Instructor del curso (solo la primera vez) | `post_save` de `GameResult`, a velocidad 1× |
| Rutina nueva en el catálogo | Todos los alumnos | `studio.services.publish` y aprobación en `backoffice` |
| Propuesta al catálogo revisada | Instructor de la rutina | `approve_for_catalog` / `reject_for_catalog` |
| Nueva versión de la app | Cuentas con teléfono registrado | `create_release` / `update_release` al publicar |
| Video del maestro listo o con error | Instructor que lo subió | `routines.tasks.generate_reference` |
| Error nuevo en la app | Administradores | `report_app_error`, solo la primera vez |

Un fallo al crear un aviso nunca rompe la acción que lo provocó (`signals.safely`).

## API (`/api/notifications/`)

| Método | Ruta | Uso |
| --- | --- | --- |
| GET | `` | Bandeja paginada, más recientes primero, con `unread` |
| POST | `read/` | Marca como leídas (`ids` opcional; sin `ids`, todas) |
| POST | `devices/` | Registra el token del teléfono (`token`, `platform`, `app_version`) |
| POST | `devices/remove/` | Al cerrar sesión: el teléfono deja de recibir avisos |

## Configuración de FCM

1. Firebase → Configuración del proyecto → Cuentas de servicio → **Generar nueva clave privada**.
2. Guardarla como `backend/secrets/firebase-admin.json` (la carpeta está en `.gitignore`).
3. `FIREBASE_CREDENTIALS=/app/secrets/firebase-admin.json` en `.env` y `docker compose up --build -d`.

Sin ese archivo no se envía nada y todo lo demás funciona. Los tokens que FCM
declara inexistentes se borran solos.
