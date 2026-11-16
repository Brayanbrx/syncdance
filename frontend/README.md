# Web de SyncDance

Angular 20 servido por nginx en el servicio `web` de Compose (puerto 8085).
nginx también es la entrada única a Django: reenvía `/api`, `/admin` y
`/static`. No expone `/media`; los archivos salen por endpoints con permisos.

| Ruta | Para quién | Qué hace |
| --- | --- | --- |
| `/` | Alumnos e instructores | Landing: cómo funciona, privacidad y descarga del APK publicado |
| `/ingresar` | Instructores y administración | Un solo ingreso: lleva al panel o al estudio según el rol |
| `/panel` | Superusuarios y rol Administrador | Resumen, usuarios, rutinas, revisión del catálogo, cursos y versiones de la app |
| `/estudio` | Instructores | Subir rutinas, ver el informe de calidad, publicarlas en sus cursos y proponerlas al catálogo |
| `/admin/` | Instructores (y administración avanzada) | Django Admin: cursos, tareas, progreso y observaciones |
| `/privacidad`, `/terminos` | Todos | Textos legales (responsable y contacto desde `/api/auth/legal/`) |
| `/cuenta/recuperar`, `/cuenta/restablecer`, `/cuenta/borrar` | Alumnos e instructores | Recuperar la contraseña y borrar la cuenta |

## Estudio del instructor

- **Mis rutinas:** cada una con su miniatura y su estado (borrador,
  procesando, con error, lista para publicar, publicada en N cursos o en el
  catálogo).
- **Subir rutina:** datos y video (MP4, MOV, WEBM o MKV, de 5 s a 5 min, hasta
  200 MB); el servidor lo revisa al subirlo.
- **Detalle:**
  - el procesamiento se actualiza solo
  - vista previa: el mismo video de 720p que descargan los alumnos
  - informe de calidad con los tramos donde no se ve a una sola persona
  - publicar en sus cursos declarando los derechos de la música
  - compás y pasos (`/estudio/rutinas/:id/pasos`): el tempo se marca tocando
    «Tiempo» o la tecla T sobre el video, con cuentas de ocho y metrónomo para
    comprobarlo; cada paso tiene nombre, inicio, duración en tiempos y un
    consejo. Los alumnos lo reciben al publicar.
  - proponerla al catálogo SyncDance y ver el resultado de la revisión
  - retirar, editar, reemplazar el video o borrar

  API en `backend/apps/studio/README.md`.

## Revisión del catálogo (`/panel/revision`)

Las rutinas que los instructores proponen, la más antigua primero, con su
miniatura, el video, el porcentaje con una sola persona visible, los derechos
de la música y en cuántos cursos está publicada. Aprobar la suma al catálogo;
rechazar pide un motivo, que el instructor lee en su estudio. El resumen del
panel muestra cuántas esperan.

## Panel de administración

- **Resumen:** cifras de personas, práctica, catálogo, cursos y la versión
  publicada (`GET /api/panel/summary/`).
- **Usuarios:** filtrar por rol, estado o texto; cambiar rol y acceso; cambiar
  la contraseña; crear cuentas de instructor o administrador. Nadie puede
  cambiar su propio rol ni desactivarse, y solo un superusuario modifica a otro.
  Volver al rol Estudiante quita el acceso al Django Admin.
- **Rutinas:** estado de la referencia, prácticas y mostrar u ocultar en el
  catálogo de la app. Videos y referencias se editan en `/admin/`.
- **Cursos:** todos los cursos con su código; progreso y edición en `/admin/`.
- **App Android:** subir un APK (se comprueba que sea un APK y se calcula su
  SHA-256), publicarlo o retirarlo, y borrar versiones no publicadas.

La sesión del panel vive en `sessionStorage` (se cierra con la pestaña) y el
token se renueva solo tras un 401.

## Desarrollo

```powershell
cd frontend
npm ci
npm start          # http://localhost:4200, con /api y /admin hacia localhost:8000
npm run lint
npm run format:check
npm test -- --watch=false --browsers=ChromeHeadless
npm run build
```

En Docker, tras cambiar la web: `docker compose up --build -d web`.

## Diseño

Tokens en `src/styles.scss`. El naranja y el celeste significan el lado
anatómico izquierdo y derecho, como en la app; el bailarín de la landing
(`features/landing/dancer.component.ts`) usa esa convención y se queda quieto
con «reducir movimiento». Tipografías alojadas en la propia web (paquetes
`@fontsource`): Bricolage Grotesque para títulos y Atkinson Hyperlegible para
el texto.
