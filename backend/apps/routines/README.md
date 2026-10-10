# Fase 3 · Paso 1 — referencias de video maestro

## Logrado

- Crear o reemplazar un video desde la API o Django Admin solicita una referencia.
  Cambiar texto no inicia procesamiento. Rutinas existentes pueden solicitarlo
  con la acción Admin «Generar nueva referencia del video maestro» o la API.
- Se asigna una versión bajo bloqueo de la rutina en PostgreSQL. El envío a
  Celery ocurre después del commit; mientras hay un trabajo vigente, se reutiliza.
- Estados PENDING → PROCESSING → READY / FAILED, con errores públicos sin rutas
  internas. Reintentar crea una versión nueva, nunca modifica un READY.
- La versión conserva la ruta del video fuente; reemplazarlo no cambia trabajos
  anteriores. Sus checksums y resultados quedan en el historial. No sobrescribir
  archivos de storage fuera de la aplicación: la ruta debe conservar su contenido.
- FFmpeg corrige rotación/metadatos de píxel, remuestrea a 12 Hz por tiempo de
  presentación y limita el lado mayor a 960 px. MediaPipe Lite extrae pose local
  en modo VIDEO; OpenCV lee el video normalizado. No se llama a IA remota.
- Se guardan un JSON gzip determinista, SHA-256 del archivo comprimido, hash del
  video original y del modelo, versiones de motor/algoritmo y duración.
- El archivo contiene `motion-features-v1`, coordenadas `body-normalized-v1` y
  seis ángulos `body-features-v1`. Usa la misma geometría y fixture que Flutter.
  Ausencias permanecen vacías; se conserva su posición en el timeline.
- El endpoint actual devuelve únicamente un READY asociado al video vigente.
  Las descargas versionadas mantienen acceso al historial autorizado.
- `GET /api/routines/{id}/references/{version}/video/` entrega el video fuente
  asociado a un READY, con JWT y visibilidad de la rutina. Devuelve ETag con
  `source_sha256`; Flutter verifica los bytes antes de reproducir. No sustituye
  un video antiguo por el maestro actual. El cliente descarga el archivo entero
  a disco antes de abrirlo, por lo que este endpoint no implementa HTTP Range.

## Ejecutar

Con Docker, reconstruir backend/celery y aplicar migraciones. La imagen incluye
dependencias nativas y el modelo oficial en `/opt/syncdance`, fuera del bind mount:

```powershell
docker compose up --build backend celery
```

Sin Docker, desde `backend/` y con el entorno virtual existente:

```powershell
.venv/Scripts/python -m pip install -r requirements-pose.txt
$env:DJANGO_SETTINGS_MODULE = 'config.settings.development'
.venv/Scripts/python manage.py install_pose_model
.venv/Scripts/python manage.py migrate
.venv/Scripts/python -m celery -A config worker --loglevel=info --pool=solo
```

El worker necesita PostgreSQL/Redis y las mismas variables que Django. `--pool=solo`
es para desarrollo en Windows; Compose usa el worker Linux habitual. El comando
de instalación descarga explícitamente el modelo Lite float16/v1 oficial, comprueba
su checksum y no reemplaza un archivo existente. La inferencia no descarga modelos.
`POSE_MODEL_PATH` permite configurar el archivo. Los binarios no se versionan en Git.

## API

Todas las rutas llevan `/api/routines/{id}/` y autenticación JWT:

| Método / ruta | Función |
| --- | --- |
| POST `generate-reference/` | Solicitar/reintentar, instructor propietario o admin; 202 con versión/estado |
| GET `reference-status/` | Estado más reciente para el video actual, incluido error |
| GET `reference/` | Último READY del video actual, checksum y `download_url`; 404 si no existe |
| GET `references/{version}/download/` | Gzip versionado, `ETag` SHA-256, permisos del catálogo |

`reference_asset` se conserva por compatibilidad. El cliente nuevo debe usar
`download_url`. En desarrollo `/media/` continúa siendo servido por Django;
autenticar esta ruta de descarga no convierte el storage público en privado.

## Contrato y límites

- Máximo 200 MB y cinco minutos por video en este primer incremento. Contenedores
  MP4/MOV, Matroska/WebM y AVI, sujetos a codecs del FFmpeg instalado.
- Timeline desde el primer frame de video, sin audio: `t = round(i*1000/12)`.
  La duración técnica se cuantiza a muestras; sincronizar con el reproductor se
  validará al integrar la rutina en Flutter. No asumir precisión de audio/edición.
- Confidence = mínimo de presence/visibility MediaPipe; filtro geométrico 0.5.
  No es equivalente estadístico a likelihood de ML Kit: hay que calibrarlo.
- Se solicitan hasta dos personas. Una muestra con varias se marca
  `MULTIPLE_PEOPLE` sin ángulos. El detector no garantiza detectar todas las personas.
- READY significa archivo procesado con al menos una muestra utilizable, no que
  toda la rutina tenga calidad suficiente. `valid_frame_ratio` permite inspeccionar
  cobertura. Los tramos vacíos no podrán puntuarse; el criterio editorial para
  publicar una rutina y la cobertura mínima se definirán con videos de prueba.
- No se suaviza ni se realiza calibración de quietud sobre el video maestro.
  Mantiene señales crudas para no añadir un desfase oculto a la referencia.
- Procesos interrumpidos en PENDING/PROCESSING durante más de 31 minutos pueden
  sustituirse mediante una nueva solicitud. El trabajo anterior se marca FAILED.
  No hay reintentos infinitos ni actualización de versiones históricas.
- Modelos Lite/ML Kit distintos y perspectiva pueden introducir diferencias.
  Las pruebas geométricas comunes no certifican precisión entre motores.

## Verificación

Resultado local (2026-10-01): 33 pruebas de lógica/API aprobadas; 2 pruebas
nativas adicionales aprobadas con FFmpeg 7.1, OpenCV 4.13.0 y MediaPipe 0.10.35.
El clip positivo repite durante un segundo la
[imagen de prueba oficial](https://storage.googleapis.com/mediapipe-assets/pose.jpg):
produjo 12 muestras y poses útiles. El clip negro se rechazó. Esto comprueba
integración y manejo de ausencia, no precisión ni rendimiento de baile real.
Ruff, comprobaciones Django, migraciones sin cambios pendientes de generar y
Swagger validado sin advertencias. Las migraciones se ejecutaron en la base de
pruebas; no se aplicaron a una base de desarrollo en ejecución.

Se instalaron dependencias y modelo en el entorno local. Docker no estaba
iniciado: no se probó el build Linux ni PostgreSQL/Redis/worker separados.
La suite normal omite las dos pruebas nativas; la ejecución explícita descrita
abajo las habilita. Los recursos descargados quedan fuera de Git.

Pruebas de unidad/integración con SQLite, storage temporal y canal Celery simulado:

```powershell
.venv/Scripts/python -m pytest
```

Pruebas opcionales del motor nativo con clips generados y sin servicios externos:

```powershell
$env:RUN_NATIVE_POSE_TESTS = '1'
# Opcional: imagen de pose local para generar un clip de un segundo.
$env:POSE_TEST_IMAGE = 'C:/ruta/pose.jpg'
.venv/Scripts/python -m pytest ai_engine/tests/test_native_reference.py -rs
```

Pendiente de Fase 3: descarga/caché móvil, reproducción y sincronización temporal,
validación con videos de baile reales y ejecución integrada PostgreSQL/Redis/worker.
Las pruebas físicas aplazadas de Fases 1–2 siguen pendientes.

Fuentes: [MediaPipe Python](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/python)
y [modelo oficial](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker).
