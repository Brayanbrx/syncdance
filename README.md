# SyncDance AI

Entrenador móvil de baile en tiempo real: seguir una referencia, analizar la
pose en el teléfono y recibir feedback técnico inmediato.

**Estado: Fase 6 implementada en código (pasos 1–3) y modo juego «Bailar»; Fase 8 (cursos, tareas y observaciones) implementada; Fase 7 (endurecimiento) iniciada; validación física de Fases 1–6 pendiente. Plataforma objetivo: Android (iOS fuera del alcance por ahora).**
Flutter incluye cámara frontal, pose ML Kit para Android, esqueleto sobre la
preview, normalización corporal, evaluación inicial del encuadre, calibración
de estabilidad y seis ángulos 2D suavizados. El benchmark físico, ajuste de
umbrales y validación del scoring siguen pendientes. El backend procesa videos maestros con
MediaPipe y publica referencias versionadas; Flutter las descarga, valida y
guarda por cuenta para consultarlas sin conexión durante la sesión. El maestro
se descarga por versión, se reproduce localmente y muestra sus medidas según
la posición del video. **Practicar con cámara** añade comparación experimental
de seis ángulos y doce posiciones normalizadas con una ventana temporal,
después de calibrar el encuadre. Ambos componentes tienen igual peso inicial.
Durante la práctica muestra una indicación geométrica a la vez para codos,
rodillas, altura de manos, separación de pies o inclinación del torso, después
de observar un error persistente. Aros amarillos señalan las articulaciones
implicadas sobre el esqueleto cuando está visible.
Al finalizar guarda similitud media, cobertura estimada, resultados por tramos
y avisos frecuentes en un historial local separado por cuenta y servidor. Los
resúmenes se sincronizan con Django mediante una cola offline idempotente, la
sesión reabre la app sin red y el historial muestra mejor marca y tendencia por
rutina con prácticas comparables.
La validación en teléfono sigue pendiente; ninguna fase está cerrada. Seguir el
[protocolo de validación física](mobile/VALIDACION_FISICA.md).

## Arquitectura

```text
Flutter: cámara -> PoseEstimator -> normalización -> comparación -> feedback
    |                      (comparación y feedback geométrico experimentales)
    | HTTP: catálogo, referencias y resúmenes
    v
Django REST + Django Admin -> PostgreSQL
    |      ^
    |      | /api, /admin
    |   nginx (web): landing con la descarga del APK + panel de administración (Angular)
    |
    Redis / Celery -> referencias y análisis posterior
```

Flutter es el producto principal. Django administra usuarios, catálogo,
referencias versionadas e historial; no recibe frames del entrenamiento.
Celery se reserva para trabajo offline. La web (Angular servida por nginx) es la
landing donde alumnos e instructores descargan la app y el panel de
administración de la plataforma; ver [frontend/README.md](frontend/README.md).

Ver [arquitectura](docs/ARQUITECTURA.md),
[ADR-001](docs/ADR-001-live-first-mobile-first.md) y
[plan maestro](docs/SyncDance_AI_PLAN_MAESTRO.md).

## Inicio rápido del backend

Requisitos: Docker y Docker Compose.

```powershell
Copy-Item .env.example .env
docker compose up --build
```

En desarrollo, Compose crea la semilla **admin / admin** (superusuario, rol
Administrador) si no existe. Para volver a esa contraseña:
`docker compose exec backend python manage.py seed_admin --reset-password`.
La semilla se niega a correr con `DEBUG` desactivado: nunca usarla en producción.

Para tener clases listas para bailar, instalar el catálogo por defecto (9 rutinas
con videos de licencia libre; ver `backend/apps/routines/README.md`):

```powershell
docker compose exec backend python manage.py load_default_catalog
docker compose exec backend python manage.py generate_standard_catalog
```

El segundo genera el **estándar SyncDance** (16 rutinas en tres niveles: pasos
básicos y una coreografía original por nivel) con coach animado, ritmo propio,
rejilla de tiempos y referencia exacta; ver
`backend/ai_engine/choreography/README.md`.

Compose aplica las migraciones al iniciar Django, sin borrar los datos
existentes.

- Web (landing y descarga del APK): http://localhost:8085/
- Panel de administración (superusuarios y rol Administrador): http://localhost:8085/panel
  (en desarrollo, la semilla `admin` / `admin`)
- Panel del instructor (Django Admin): http://localhost:8085/admin/
- API: http://localhost:8085/api/ (también directa en el puerto 8000)
- Swagger: http://localhost:8000/api/docs/
- Health: http://localhost:8000/api/health/

Para abrir la landing desde un teléfono de la misma red: `http://<IP-del-PC>:8085/`,
con esa IP añadida a `DJANGO_ALLOWED_HOSTS` en `.env`.

Cuentas: recuperar la contraseña (`/cuenta/recuperar`, también desde el login
de la app) y borrar la cuenta (`/cuenta/borrar` y **Mi cuenta** en la app). En
desarrollo el correo con el enlace se imprime en el log de `celery`.

**Producción:** `docker-compose.prod.yml` con HTTPS (Caddy), gunicorn y copias
de seguridad diarias. Guía de despliegue, copias y restauración en
[ops/README.md](ops/README.md).

Para trabajar sin Docker: Python 3.12, PostgreSQL y Redis. Crear el entorno con
`python -m venv backend/.venv`, instalar `backend/requirements.txt` y definir las
variables de `backend/.env.example` en el shell (Django no carga ese archivo
automáticamente). Con PostgreSQL local, usar `POSTGRES_HOST=localhost`.

## Flutter

Base verificada con Flutter 3.44.2 / Dart 3.12.2. Desde `mobile/`:

```powershell
flutter pub get
flutter run
```

La configuración predeterminada proviene de `.env.example`, incluida como asset;
no hace falta crear un archivo `.env` para compilar. Para teléfono físico:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api
```

Reemplazar la IP por la del equipo con Django y permitir ese host en
`DJANGO_ALLOWED_HOSTS`. Android Emulator usa `10.0.2.2`. La URL del cliente es
pública y nunca debe contener secretos. Para repartir un APK firmado con una
clave propia, ver [mobile/android/README.md](mobile/android/README.md).

**Mis cursos** (en Inicio): el alumno se une con el código que le da su
instructor, ve cada tarea con su objetivo en estrellas, su mejor marca ya
sincronizada y la fecha límite, la baila con un toque y lee las observaciones
del instructor. El instructor crea cursos y tareas, revisa el progreso y comenta
prácticas en el Django Admin. Ver `backend/apps/coaching/README.md`.

**Bailar** (en Inicio) lleva al catálogo: un toque descarga referencia y video
y abre el modo juego manos libres, con calificaciones al ritmo, combo,
pictogramas de los próximos movimientos, estrellas y **Practicar** cada
movimiento débil en bucle y más lento. Ver
`mobile/lib/features/training/game/README.md`.

El login y el catálogo móvil están conectados a Django. **Crear cuenta de
estudiante** (en el login) registra con rol Estudiante; el servidor aplica los
validadores de contraseña de Django y la app entra sola al terminar. La sesión persiste en
almacenamiento seguro (identidad y refresh token, nunca la contraseña): la app
reabre sin red y renueva el acceso al reconectar.
`features/training/pose/` contiene `PoseEstimator`, los 33 joints canónicos y
`PoseFrame`, independientes de cualquier proveedor.

Para probar la cámara: **Continuar sin cuenta → Inicio → Preparar cámara**.
La cámara no requiere backend. Android requiere versión 7.0
(API 24) o superior. La prueba no graba, no sube imágenes ni solicita micrófono.
Los valores de imágenes/s corresponden a captura, no a inferencias de pose.
Ver [registro de pasos y prueba manual](mobile/lib/features/training/README.md).

El siguiente acceso, **Inicio → Detectar postura**, conecta ML Kit en Android.
Muestra un esqueleto que puede ocultarse, landmarks recibidos, confianza media,
tiempo de inferencia y frames descartados. La izquierda anatómica es naranja y
la derecha celeste; el espejo solo afecta al dibujo. La confianza no es un score técnico ni reemplaza el futuro quality
gate. La pantalla permanece encendida durante la captura y recupera el
comportamiento normal al salir. iOS queda fuera del alcance por ahora: no hay
adaptador de pose iOS ni se compila para iOS.

En esa pantalla también se muestran ángulos 2D de codos, hombros y rodillas,
separados por lado anatómico. `—` significa que faltan puntos válidos; no se
rellena con cero. La normalización usa centro de caderas y longitud del torso,
con corrección de proporción de imagen. Son medidas geométricas experimentales,
sin comparación con una rutina ni puntuación. En horizontal las medidas aparecen
al lado de la cámara; en vertical, debajo en un panel desplazable.

Para descargar referencias: **Ingresar con una cuenta de Django → Rutinas →
Descargar referencia**. Se comprueban SHA-256, esquemas, timeline y medidas antes
de publicar la versión en disco. Las versiones anteriores sobreviven a una
descarga fallida; cada cuenta y servidor tienen su propia carpeta de caché.
Desde **Referencias guardadas** se consultan duración, muestras y cobertura,
y se elimina cada versión. La consulta funciona sin red durante la sesión;
tras cerrar la app se necesita red para autenticar la cuenta otra vez.
Para ver el maestro: tocar una referencia guardada → **Abrir maestro → Descargar
video y abrir**. El video se verifica contra el hash de esa versión y queda
disponible sin red durante la sesión. Incluye reproducir/pausar, saltar, volver al
inicio y eliminar el video. **Practicar con cámara** abre la cámara frontal en
la misma pantalla: calibrar quieto con el maestro pausado y luego reproducir.
La similitud 0–100 combina seis ángulos y doce posiciones corporales, con detalle
de cada componente; se retira al pausar, saltar o perder
calidad. **Finalizar práctica**, o llegar al final del video, muestra un resumen
experimental con cobertura estimada y tramos de cinco segundos. Las zonas sin
datos permanecen sin puntuación. **Repetir práctica** reinicia desde cero.
El resumen se guarda automáticamente en el dispositivo y se consulta desde
**Inicio → Historial de prácticas**. Incluye los tres avisos más frecuentes
realmente mostrados, sin interpretar ausencia de avisos como ausencia de errores.
Se puede abrir el detalle o eliminar una práctica. Si falla el guardado, el
resumen sigue visible para reintentar; repetir se habilita después de guardarlo.
Volver atrás durante la práctica la finaliza y muestra el resumen antes de salir.
Los registros sobreviven al reinicio, pero se requiere autenticar de nuevo la
misma cuenta para consultarlos. Se envían al servidor con la cola offline. Ver
[historial local](mobile/lib/features/training/history/README.md),
[feedback en vivo](mobile/lib/features/training/feedback/README.md),
[comparación](mobile/lib/features/training/comparison/README.md),
[referencias móviles](mobile/lib/features/routines/reference/README.md)
y [reproducción](mobile/lib/features/training/playback/README.md).

Antes de mostrar medidas, se requieren cabeza y articulaciones principales
visibles y confiables. La pantalla guía para mejorar el encuadre y solicita
mantener el torso estable al menos un segundo (mínimo ocho muestras válidas).
Después muestra ángulos suavizados y permite **Recalibrar encuadre**. Al perder
la calidad, girar o pausar se retiran las medidas y se calibra de nuevo.
Los umbrales son iniciales: falta ajustar su tolerancia en teléfono. No se
detecta multiplicidad de personas ni se certifica orientación frontal.

## ¿Necesitamos una API de IA generativa?

Para la detección corporal actual, no. ML Kit procesa la pose en el teléfono y
el modelo Android está incluido en la aplicación; no se configura una clave de
Gemini ni se envían imágenes a una API remota. El plan prevé normalización,
scoring y feedback mediante algoritmos locales, también sin un LLM.

Gemini u otro proveedor sería opcional para redactar un resumen a partir de
errores medidos e historial (sección 43 del plan). Si se incorpora, Django hará
la petición con credenciales del servidor; ninguna clave secreta irá en Flutter.
El proveedor no calculará el score ni bloqueará el entrenamiento. Esta integración
todavía no existe. La API de Django para catálogo/historial es independiente.

Fuentes: [ML Kit local/offline](https://developers.google.com/ml-kit),
[modelo Android incluido](https://developers.google.com/ml-kit/vision/pose-detection/android),
[autenticación de Gemini](https://ai.google.dev/gemini-api/docs/api-key).

## Dominio preparado

- `RoutineReference`: archivo de referencia y metadatos versionados; estados
  PENDING / PROCESSING / READY / FAILED. API y Admin encolan generación con Celery
  al cargar/cambiar video; FFmpeg/OpenCV/MediaPipe procesan localmente el maestro.
- `DanceSession`: sesión sin video obligatorio, versión de referencia y de
  algoritmos, scores opcionales y ratio de calidad.
- `SegmentScore` y `ErrorEvent`: resumen técnico, sin persistir cada frame.
- `Performance` y `/api/performances/`: flujo secundario compatible. Su tarea
  Celery conserva resultados **simulados** de baile; `voice_score` es nullable.
  El móvil ya no lo ofrece en Inicio (contradice el enfoque live-first); sus
  rutas se conservan hasta decidir su retiro.

API nueva, autenticada con JWT:

| Endpoint | Función |
| --- | --- |
| `GET /api/routines/{id}/reference/` | Última referencia READY accesible; 404 si no existe |
| `POST /api/routines/{id}/generate-reference/` | Solicitar una versión para el video actual; instructor propietario/admin |
| `GET /api/routines/{id}/reference-status/` | Estado/error de la versión más reciente del video actual |
| `GET /api/routines/{id}/references/{version}/download/` | Descargar JSON gzip versionado con checksum y permisos |
| `GET /api/routines/{id}/references/{version}/video/` | Descargar el video fuente de esa versión con los mismos permisos |
| `POST /api/training/sessions/` | Guardar una sesión y sus segmentos/eventos de forma atómica |
| `GET /api/training/sessions/` | Historial paginado del usuario autenticado |
| `GET /api/training/sessions/{uuid}/` | Consultar su propio resumen |
| `GET /api/coaching/courses/` | Cursos del alumno con tareas y su progreso |
| `POST /api/coaching/courses/join/` | Unirse con el código del instructor |
| `POST /api/coaching/courses/{id}/leave/` | Salir de un curso |
| `GET /api/coaching/notes/` | Observaciones del instructor sobre las prácticas propias |

El backend guarda scores calculados por el cliente; todavía no certifica su
precisión. Las sesiones no se editan por API. El teléfono los sube con una cola
offline: reenviar el mismo UUID desde la misma cuenta devuelve 200 con la copia
guardada (sin duplicar hijos) y un UUID de otra cuenta devuelve 409. Las
partidas del modo juego añaden su bloque `game`. Ver
`backend/apps/training/README.md`.
Los valores sin evidencia permanecen `null`, no se convierten en cero.
El login admite 10 intentos por minuto por nombre de cuenta, el registro 100
por hora por dirección y unirse a un curso 20 códigos por hora por cuenta; la
renovación del token no se limita.

Logs: Django y Celery escriben una línea JSON por evento en la salida estándar
(`docker compose logs backend celery`), con identificadores como
`reference_id`, `task_id` o `session_id`, nunca frames ni contraseñas.
`DJANGO_LOG_FORMAT=text` los muestra como texto y `DJANGO_LOG_LEVEL` fija el
nivel. Cada versión de referencia guarda su `task_id` de Celery y cuánto tardó
(Admin → Referencias).

## Validación

Backend, desde `backend/` (SQLite de pruebas, sin servicios externos):

```powershell
.venv/Scripts/python -m ruff check .
.venv/Scripts/python manage.py check --settings=config.settings.test
.venv/Scripts/python manage.py makemigrations --check --dry-run --settings=config.settings.test
.venv/Scripts/python manage.py spectacular --validate --fail-on-warn --settings=config.settings.test --file .venv/schema.yml
.venv/Scripts/python -m pytest
```

Flutter, desde `mobile/`:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

La CI ejecuta estos controles. La prueba Celery usa ejecución eager: verifica la
tarea, pero no sustituye la comprobación de Redis/worker en Docker.

## Siguiente paso

La sincronización offline, la mejor marca por rutina, el modo juego (ritmo,
pictogramas, estrellas y práctica por movimiento) y los cursos con tareas ya
están en código. Lo siguiente es la validación física con baile real
(`mobile/VALIDACION_FISICA.md`); **Detectar postura → Medir rendimiento 60 s**
da el benchmark de cada teléfono.
La métrica de ritmo y sus
avisos siguen pendientes de evidencia temporal fiable. Al retomar el
teléfono, completar alineación de overlay, benchmark y
ajuste de calibración/umbrales antes de declarar cerradas las Fases 1–2.
También falta validar la sincronización y similitud con baile real antes de
considerar cerrado el entrenador y ajustar los avisos con evidencia. Ver el
[registro de pasos](mobile/lib/features/training/README.md). Canto y LLM
quedan para fases posteriores.

El backend de Fase 3 requiere `requirements-pose.txt` y el modelo oficial.
El Dockerfile prepara ambos; para el entorno virtual, ejecutar
`python -m pip install -r requirements-pose.txt` y `python manage.py install_pose_model`
desde `backend/`, además de las migraciones. Ver [pipeline, límites y pruebas](backend/apps/routines/README.md).

Para publicar una versión de la app: `flutter build apk --release` (ver
[mobile/android/README.md](mobile/android/README.md)) y subir el APK en
**Panel → App Android**. La landing ofrece la versión publicada con el código
más alto.

## Convenciones

Monolito modular, features pequeñas y algoritmos explicables. En Django:
`views` para HTTP, `services` para cambios, `selectors` para consultas y `tasks`
para trabajo offline. En Flutter: organización por feature, con interfaces solo
en límites sustituibles. No subir frames al servidor ni inventar scores reales.

Mantener `main` estable, ramas `feature/*` / `fix/*`, Conventional Commits y PR
pequeñas con un incremento demostrable. No se necesitan microservicios ni
infraestructura adicional para comenzar.
