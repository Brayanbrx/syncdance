# Plataforma (backoffice)

API del panel web de administración y de la descarga pública de la app.

## Descarga pública (sin cuenta)

| Endpoint | Función |
| --- | --- |
| `GET /api/app/latest/` | Versión publicada con el código más alto (404 si no hay) |
| `GET /api/app/download/` | Descarga ese APK (`application/vnd.android.package-archive`) |

## Panel (`IsPlatformAdmin`: superusuario o rol Administrador)

| Endpoint | Función |
| --- | --- |
| `GET /api/panel/summary/` | Cifras agregadas, sin nombres ni puntajes |
| `GET/POST /api/panel/users/` | Listar (`role`, `active`, `search`) y crear cuentas |
| `PATCH /api/panel/users/{id}/` | Rol, acceso, nombre y correo |
| `POST /api/panel/users/{id}/set-password/` | Nueva contraseña (validadores de Django) |
| `GET/PATCH /api/panel/routines/` | Catálogo con estado de referencia; solo cambia `is_active` |
| `GET /api/panel/courses/` | Todos los cursos con su código |
| `GET/POST/PATCH/DELETE /api/panel/releases/` | Versiones del APK (multipart al subir) |

Reglas:

- Un APK debe terminar en `.apk`, empezar como un zip (`PK\x03\x04`) y pesar
  hasta 250 MB; se guarda su SHA-256 y su tamaño. El código de versión es único.
- Una versión publicada no se borra: primero se retira de la landing.
- Nadie cambia su propio rol ni se desactiva; solo un superusuario modifica a
  otro superusuario. Pasar a Estudiante quita `is_staff`.
- Un superusuario siempre tiene el rol Administrador (también los creados con
  `createsuperuser`).

`/api/auth/me/` incluye `is_platform_admin` para que la web muestre el panel.
