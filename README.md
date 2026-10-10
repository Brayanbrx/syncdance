# SyncDance AI

Entrenador móvil de baile en tiempo real: seguir una referencia, analizar la
pose en el teléfono y recibir feedback técnico inmediato.

**Estado: Fase 6 implementada en código (pasos 1–3); validación física de Fases 1–6 pendiente.**
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
    |
    Redis / Celery -> referencias y análisis posterior
```

Flutter es el producto principal. Django administra usuarios, catálogo,
referencias versionadas e historial; no recibe frames del entrenamiento.
Celery se reserva para trabajo offline. Angular está **congelado hasta Fase 11**
y se ejecuta únicamente mediante el perfil opcional `web` de Compose.

Ver [arquitectura](docs/ARQUITECTURA.md),
[ADR-001](docs/ADR-001-live-first-mobile-first.md) y
[plan maestro](docs/SyncDance_AI_PLAN_MAESTRO.md).

## Inicio rápido del backend

Requisitos: Docker y Docker Compose.

```powershell
Copy-Item .env.example .env
docker compose up --build
docker compose exec backend python manage.py createsuperuser
```

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

Ejecutar `createsuperuser` en otra terminal. Compose aplica las migraciones al
iniciar Django, sin borrar los datos existentes.

- API: http://localhost:8000/api/
- Swagger: http://localhost:8000/api/docs/
- Administración temporal: http://localhost:8000/admin/
- Health: http://localhost:8000/api/health/

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
`DJANGO_ALLOWED_HOSTS`. Android Emulator usa `10.0.2.2`; iOS Simulator puede usar
`localhost`. La URL del cliente es pública y nunca debe contener secretos.

**Bailar** (en Inicio) lleva al catálogo: un toque descarga referencia y video
y abre el modo juego manos libres, con calificaciones al ritmo, combo,
pictogramas de los próximos movimientos, estrellas y **Practicar** cada
movimiento débil en bucle y más lento. Ver
`mobile/lib/features/training/game/README.md`.

El login y el catálogo móvil están conectados a Django. La sesión persiste en
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
comportamiento normal al salir. El target iOS se elevó a 15.5 por la dependencia
ML Kit, pero el adaptador de pose iOS y su compilación siguen pendientes.

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
misma cuenta para consultarlos. No se sincronizan todavía. Ver
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

El backend guarda scores calculados por el cliente; todavía no certifica su
precisión. Las sesiones no se editan por API. El cliente debe enviar el resumen
al terminar; un UUID repetido devuelve 409 y no duplica hijos. La cola offline,
los reintentos automáticos y el flujo de sincronización móvil son trabajo de Fase 6.
Los valores sin evidencia permanecen `null`, no se convierten en cero.

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

El próximo desarrollo continúa Fase 6: sincronización de resúmenes con Django,
cola offline/reintentos y resolución de UUID duplicados. Después quedan mejor
marca personal y tendencia por rutina con criterios de comparabilidad y cobertura.
El paso 1 ya conserva resúmenes y avisos frecuentes en el historial local.
La métrica de ritmo y sus
avisos siguen pendientes de evidencia temporal fiable. Al retomar el
teléfono, completar alineación de overlay, benchmark y
ajuste de calibración/umbrales antes de declarar cerradas las Fases 1–2.
También falta validar la sincronización y similitud con baile real antes de
considerar cerrado el entrenador y ajustar los avisos con evidencia. Ver el
[registro de pasos](mobile/lib/features/training/README.md). Canto, Angular y LLM
quedan para fases posteriores.

El backend de Fase 3 requiere `requirements-pose.txt` y el modelo oficial.
El Dockerfile prepara ambos; para el entorno virtual, ejecutar
`python -m pip install -r requirements-pose.txt` y `python manage.py install_pose_model`
desde `backend/`, además de las migraciones. Ver [pipeline, límites y pruebas](backend/apps/routines/README.md).

Para iniciar la web conservada: `docker compose --profile web up --build`.
No es necesaria para desarrollar ni validar el producto móvil.

## Convenciones

Monolito modular, features pequeñas y algoritmos explicables. En Django:
`views` para HTTP, `services` para cambios, `selectors` para consultas y `tasks`
para trabajo offline. En Flutter: organización por feature, con interfaces solo
en límites sustituibles. No subir frames al servidor ni inventar scores reales.

Mantener `main` estable, ramas `feature/*` / `fix/*`, Conventional Commits y PR
pequeñas con un incremento demostrable. No se necesitan microservicios ni
infraestructura adicional para comenzar.
