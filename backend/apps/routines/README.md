# Fase 3 · Paso 1 — referencias de video maestro

## Logrado

- Crear o reemplazar un video desde la API o Django Admin solicita una referencia.
  Cambiar texto no inicia procesamiento. Rutinas existentes pueden solicitarlo
  con la acción Admin «Generar nueva referencia del video maestro» o la API.
- Se asigna una versión bajo bloqueo de la rutina en PostgreSQL. El envío a
  Celery ocurre después del commit; mientras hay un trabajo vigente, se reutiliza.
- Estados PENDING → PROCESSING → READY / FAILED, con errores públicos sin rutas
  internas. Reintentar crea una versión nueva, nunca modifica un READY.
- Si un worker muere, Celery Beat ejecuta `expire_stale_references` cada 10 min:
  una versión PROCESSING o PENDING con más de 31 min (pasado el límite duro de
  30 min) pasa a FAILED. Son UPDATE condicionales, seguros de repetir; una tarea
  que termine tarde comprueba su estado bajo bloqueo y no publica.
- La versión conserva la ruta del video fuente; reemplazarlo no cambia trabajos
  anteriores. Sus checksums y resultados quedan en el historial. No sobrescribir
  archivos de storage fuera de la aplicación: la ruta debe conservar su contenido.
- **Versión para la app** (`app-video-v1`, `ai_engine/playback/app_video.py`): antes
  de medir, el worker convierte el video subido a MP4 H.264/AAC con el lado corto
  de 720 px como máximo, 30 cuadros/s constantes desde 0 ms, la rotación aplicada
  y el audio recortado o completado con silencio hasta el final de la imagen. Si
  la imagen empieza después que el sonido, se repite el primer cuadro para no
  perder la sincronía. Se quitan los metadatos (la ubicación GPS que guardan los
  teléfonos). La referencia se calcula **sobre este archivo**, no sobre el subido:
  `source_sha256` es su hash y la línea de tiempo `video-start-cfr-v1` coincide
  con lo que reproduce el teléfono. El original queda en `source_video` para
  volver a procesar; cambiar los comandos de conversión sube `app-video-v1`.
- Una miniatura JPEG (640 px de lado mayor) sale del cuadro con una sola persona
  más cercano a un cuarto del video. Si falla, la referencia queda lista igual.
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
- `GET /api/routines/{id}/references/{version}/video/` entrega el video de esa
  versión: la versión para la app, o el video subido en versiones anteriores a
  `app-video-v1` y en las coreografías generadas. Exige un READY, JWT y
  visibilidad de la rutina. Devuelve ETag con
  `source_sha256`; Flutter verifica los bytes antes de reproducir. No sustituye
  un video antiguo por el maestro actual. El cliente descarga el archivo entero
  a disco antes de abrirlo, por lo que este endpoint no implementa HTTP Range.

## Ejecutar

Con Docker, reconstruir backend/celery y aplicar migraciones. La imagen incluye
dependencias nativas y el modelo oficial en `/opt/syncdance`, fuera del bind mount:

```powershell
docker compose up --build backend celery celery-beat
```

`celery-beat` debe tener una sola instancia.

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
| GET `references/{version}/video/` | Video que reproduce el teléfono (`ETag` = `source_sha256`) |
| GET `references/{version}/poster/` | Miniatura JPEG; 404 si esa versión no tiene |

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

## Catálogo por defecto (clases tipo Just Dance)

```powershell
docker compose exec backend python manage.py load_default_catalog
```

Crea las rutinas que falten a partir de `data/default_catalog.json` y encola
sus referencias. Es idempotente por `catalog_key`; `--only clave …` instala
algunas. Los videos se descargan de su origen al instalar y **nunca se suben al
repositorio**: la licencia permite usarlos, no redistribuir los archivos.

- **Origen y licencia:** clips de [Mixkit](https://mixkit.co/free-stock-video/dance/)
  bajo «Mixkit Stock Video Free License» (uso gratuito, también comercial, sin
  atribución obligatoria). Cada página se comprobó: se descartaron clips con la
  licencia restringida («Girl dancing outdoors», «Ballerina spins in black tutu»).
- **Seguridad:** solo HTTPS desde `assets.mixkit.co`, límite de 200 MB y SHA-256
  fijado por entrada; un archivo distinto no se instala.
- **Procedencia:** `style`, `source_url`, `license_name` y `credit` quedan en la
  rutina y la API; el móvil muestra el crédito.
- **Selección con datos:** 283 clips de categorías de baile → 45 candidatos por
  título → análisis con el mismo generador de referencias. Se eligieron los que
  tienen una sola persona y cuerpo entero medible (6 ángulos) en 60–99 % de las
  muestras y casi todos sus movimientos de 1 s calificables. La mayoría de clips
  de stock no sirven: cuerpo cortado, poca luz o varias personas.
- **Dificultad:** velocidad angular media del maestro (< 80 °/s principiante,
  80–180 intermedio, > 180 avanzado).

| Rutina | Estilo | Nivel | Duración | Medible |
|---|---|---|---|---|
| Baile alegre para empezar | Libre | Principiante | 13,8 s | 84 % |
| Ballet en sala blanca | Ballet | Principiante | 22,8 s | 90 % |
| Ballet: brazos y giros | Ballet | Intermedio | 27,1 s | 87 % |
| Coreografía con energía | Urbano | Intermedio | 24,6 s | 74 % |
| Coreografía urbana nocturna | Urbano | Intermedio | 22,5 s | 94 % |
| Reto rápido de hip hop | Hip hop | Avanzado | 6,3 s | 99 % |
| Coreografía callejera | Urbano | Avanzado | 21,5 s | 80 % |
| Urbano de cuerpo entero | Urbano | Avanzado | 13,6 s | 83 % |
| Baile en la cancha | Urbano | Avanzado | 21,9 s | 60 % |

Limitaciones: los clips **no tienen audio**, y la música gratuita de Mixkit
excluye su uso en videojuegos, así que no se añadió. Para música habría que
usar pistas CC BY que permitan juegos (citando al autor) y mezclarlas al
instalar; su ritmo no coincidirá con el del bailarín. Los maestros son de
stock: bailan libremente, no enseñan paso a paso.
