# Arquitectura live-first / mobile-first

Decisión vigente: [ADR-001](ADR-001-live-first-mobile-first.md).
Producto y secuencia: [Plan maestro v2](SyncDance_AI_PLAN_MAESTRO.md).

## Responsabilidades

```text
Flutter
  captura -> PoseEstimator -> PoseFrame -> quality gate / normalización
          -> features -> referencia local -> score -> feedback -> resumen
     |
     HTTP para catálogo, descarga y sincronización de resúmenes
     v
Django REST / Django Admin -> PostgreSQL + almacenamiento de archivos
     |
     Redis -> Celery -> ai_engine (preprocesamiento / análisis offline)
```

El loop completo en Flutter es el objetivo; actualmente hay captura y un adaptador
ML Kit para pose en Android, overlay de esqueleto, normalización y seis ángulos
2D, quality gate inicial, calibración de encuadre y suavizado. La validación
física y ajuste de umbrales siguen pendientes. Hay una primera similitud
experimental de ángulos y posiciones en la sesión conjunta y resumen con cobertura
estimada, persistido en el dispositivo con historial por cuenta y servidor.
El entrenamiento deberá funcionar offline después de descargar
rutina y referencia. Ni Django ni Redis participan por frame. Angular permanece
congelado y opcional (`docker compose --profile web up`).

## Módulos backend

| Módulo | Responsabilidad actual |
| --- | --- |
| `accounts` | Usuarios, roles y JWT |
| `routines` | Catálogo, video maestro, duración y referencias versionadas |
| `training` | DanceSession, SegmentScore, ErrorEvent y API de resúmenes privados |
| `performances` | Compatibilidad con cargas y tareas offline anteriores |
| `analysis` | Resultado offline heredado; voz opcional |
| `ai_engine` | Extracción offline MediaPipe y geometría corporal, sin modelos Django |

No se renombra ni elimina la tabla `Performance`: las migraciones son aditivas
y conservan el historial existente. Una performance simulada no se transforma en
una sesión live real. `Analysis.voice_score` admite null conservando los datos y
el nombre para clientes anteriores; el módulo vocal independiente llega en Fase 9.

Las rutinas conservan `name`, `instructor` e `is_active` por compatibilidad.
`is_active` controla visibilidad para alumnos; no se introduce todavía otro
campo de publicación con semántica duplicada. Las referencias tienen versiones
únicas por rutina y no se almacenan como filas por frame. Una referencia READY
requiere archivo, checksum SHA-256, duración, motor y versión de algoritmo al validarse en Admin.
Las referencias READY no se editan desde Admin: se crea una versión nueva.

Fase 3, paso 1: `reference_services.queue_reference` asigna versiones con bloqueo
por rutina y publica la tarea después del commit. Conserva `source_video`, hash
del video y fecha de inicio. El worker extrae en directorio temporal con límites
de duración/tamaño, crea gzip determinista y publica READY solo tras guardar el
archivo y validarlo. Fallos de cola/procesamiento producen FAILED. Nuevas
solicitudes recuperan trabajos vencidos en más de 31 minutos creando otra versión.
La rutina actual no recibe resultados de un video sustituido.

El procesamiento normaliza orientación, proporción de píxel y frecuencia con
FFmpeg (12 Hz), lee con OpenCV y extrae MediaPipe Lite local. `ai_engine/features/body.py`
comparte geometría/fixture con Flutter. No se aplican suavizado ni espera de
calibración al maestro. Las muestras ausentes o ambiguas siguen en el timeline
sin medidas. READY no implica aprobación técnica de toda la rutina: cobertura
y precisión deberán validarse antes de puntuar. Ver `backend/apps/routines/README.md`.

Las sesiones guardan el UUID del cliente y una instantánea de las versiones de
pose, features y referencia tomadas por el servidor. El cliente declara su versión
de scoring. Un score ausente se guarda como null. Un usuario solo puede consultar
sus sesiones; la revisión por instructores requiere las relaciones de Fase 8.

`POST /api/training/sessions/` guarda resumen e hijos en una transacción; rechaza rangos,
fechas incoherentes, referencias no disponibles, eventos fuera de duración y
segmentos duplicados. Los duplicados UUID devuelven 409; no hay actualizaciones
ni merge automático. No es todavía una cola de sincronización móvil.

## Móvil

`features/training/pose/` es Dart independiente del motor nativo. Incluye:

- `Joint`: nombres anatómicos canónicos.
- `PoseLandmark`: coordenadas finitas y confianza [0, 1].
- `PoseFrame`: landmarks inmutables, joints ausentes y timestamp monotónico.
- `PoseEstimator`: stream local y liberación de recursos.

`pose-v1` usa imagen vertical corregida, origen superior izquierdo, x hacia la
derecha e y hacia abajo, normalizadas por ancho/alto. Se permiten posiciones
fuera de [0, 1] para quality gate. La profundidad opcional usa unidades de ancho
de imagen. Izquierda/derecha son anatómicas y no cambian con la preview espejo.
Cada frame incluye la proporción ancho/alto de la imagen corregida; los futuros
cálculos deben usarla para recuperar la geometría antes de medir ángulos.
Cada adaptador deberá transformar la salida de su SDK a este contrato.

El primer adaptador de Fase 1 usa ML Kit base en modo stream, detrás de
`PoseEstimator`, mediante un puente Flutter comunitario. Su aprobación definitiva
depende del benchmark físico. La captura Android produce NV21 y transmite frames
efímeros al adaptador, con una inferencia máxima simultánea y descarte de frames
ocupados/obsoletos. La confianza media mostrada no es un score ni un quality gate.
La detección de este incremento es Android-first; iOS queda pendiente.
La comparación de Fase 4 combina ángulos y posiciones normalizadas;
la sincronización de resúmenes sigue pendiente. Fase 3, paso 2 conecta
login JWT, catálogo paginado y descarga autenticada de referencias en Flutter.
`features/routines/reference/` valida SHA-256 sobre gzip, versiones, procedencia,
timeline a 12 Hz, ángulos y cobertura antes de guardar. Las muestras con torso
normalizado pero sin ángulos siguen siendo `NO_USABLE_POSE` y no cuentan como
medidas utilizables. La fixture compartida se regenera con Python y se lee en Dart.

La caché reside en el almacenamiento privado de la app, separada por servidor y
cuenta. Cada versión se escribe mediante un archivo temporal y rename; se
revalida al leer y se conserva si falla otra descarga. Límites: 8 MiB comprimidos,
16 MiB descomprimidos, 12 MiB por archivo de caché y 64 MiB por cuenta/servidor.
El parseo y la verificación se ejecutan fuera del isolate de UI. Los tokens solo
viven en memoria, sin renovación automática: al reiniciar se requiere login
online. La consulta offline actual es dentro de una sesión ya autenticada; no
incluye entrenamiento offline completo.

Fase 4, paso 1: `MasterVideoCache` añade descarga a disco y SHA-256 del video
fuente versionado, antes de abrir `video_player` con archivo local. El endpoint
`references/{version}/video/` resuelve `source_video` de esa referencia y aplica
los permisos de la rutina. Las carpetas de video quedan dentro de la caché de
cada cuenta/servidor, con 200 MiB por video y 512 MiB en total; se pueden borrar
desde el reproductor o al eliminar la referencia.

`ReferenceTimeline` consulta la última muestra cuyo timestamp no supera la
posición del reproductor. No inventa un reloj por tiempo transcurrido ni rellena
huecos. Un cambio de posición vuelve a consultar el índice; buffering, background,
fin o búsqueda pendiente retiran medidas. La pausa permite inspeccionar la
muestra detenida. Una discrepancia de duración mayor a 250 ms impide reproducir
con esta referencia. Este umbral inicial y la alineación física requieren
validación. La sesión conjunta se incorpora en el paso siguiente.

Fase 4, paso 2: `LiveComparisonPanel` reutiliza captura/pose/calibración en modo
embebido dentro del reproductor. Antes de inferir, `CaptureVideoClock` asocia el
timestamp de cámara con la última posición del video notificada, sin guardar
buffers ni extrapolar. Descarta posiciones sin cambios durante más de 250 ms,
resultados de inferencia con más de 500 ms y registros anteriores a pausa/salto,
buffering, cambio de cámara/orientación o background. Conserva como máximo 64
registros. La similitud mostrada vence tras 250 ms sin resultado nuevo.

`AngleMatcher` (`angle-window-v1`) requiere quality gate/calibración del alumno y
seis ángulos válidos de ambos lados anatómicos. Usa ángulos sin suavizado para
evitar el retraso de la EMA de presentación. Busca el menor error medio absoluto
en ±200 ms, sin atravesar tramos incompletos; similitud = clamp(100 × (1 − MAE/90),
0, 100). El desplazamiento elegido no es un score de timing. No guarda resultados
en Django. Fórmula y tolerancias son experimentales,
pendientes de validación conjunta en teléfono.
La fixture inicial es sintética; no implica validación biomecánica ni precisión.

Fase 4, paso 3: `SessionAccumulator` (`angular-summary-v1`) conserva la primera
comparación válida en cada intervalo de 100 ms del video. El promedio pondera
la duración de esos intervalos, recortando el último al final de la referencia.
La cobertura estimada divide esa duración evaluada entre toda la rutina; los
saltos, calibración y huecos sin evidencia no se rellenan con cero. Repetir
un tramo puede llenar intervalos vacíos, pero nunca sustituye datos existentes.
El resumen incluye segmentos de cinco segundos; sin evidencia, el score es null.
Finalizar manualmente, llegar al final o un error del reproductor congela el
resultado antes de cerrar la cámara. Inferencias tardías no lo alteran. Repetir
crea otro acumulador y pausa el maestro al inicio. Fase 6, paso 1 añade el guardado
del resumen y el historial local descritos abajo; la sincronización sigue pendiente.

Fase 4, paso 4: `MotionSample` conserva las coordenadas normalizadas validadas
del archivo existente. `PoseMatcher` (`pose-window-v1`) exige seis ángulos y
doce posiciones de hombros, codos, muñecas, caderas, rodillas y tobillos.
Compara distancias 2D en largos de torso, con origen en el centro de caderas,
sin rotar el torso ni intercambiar lados anatómicos. El componente de posiciones
es clamp(100 × (1 − distancia media), 0, 100); la similitud combina 50 % de
ángulos y 50 % de posiciones. Pesos y umbrales siguen siendo experimentales.
Busca la mejor similitud conjunta en ±200 ms: ambas métricas pertenecen a la
misma muestra, y los huecos de posiciones también detienen la búsqueda.
No hay fallback angular ante posiciones incompletas. `pose-summary-v1` conserva
la ponderación temporal y agrega ambos componentes, errores y versiones.
Las proporciones corporales y perspectiva pueden afectar las posiciones;
la invariancia sintética a escala/traslación no valida precisión entre personas.

Fase 5, paso 1: `FeedbackRules` (`geometric-feedback-v1`) usa las features del
alumno y `PoseMatch.referenceSample`, la misma muestra seleccionada para el score.
Genera diferencias con signo para codos/rodillas (20°), altura de manos (0.25
largos de torso) y separación horizontal de tobillos (0.30). Cada candidato tiene
código, región, métrica, magnitud, umbral, severidad y acción concreta.
`LiveFeedback` exige 400 ms y cuatro muestras, separadas por como máximo 250 ms;
selecciona un aviso por severidad y mantiene histéresis al 60 % del umbral.
La tarjeta se renueva con evidencia, con duración objetivo de 1200 ms, separación
de 1500 ms entre inicios y descanso por región de 1500 ms desde su retirada.
Invalidar calidad/reloj retira avisos de inmediato; la expiración del score a
250 ms también borra la evidencia. Nueva sesión o referencia crea otro controlador.
No se generan avisos de ritmo a partir del offset. Fase 6, paso 1 agrega conteos
de avisos mostrados al resumen; no guarda poses por frame. La validación física
sigue pendiente.

Fase 5, paso 2: `geometric-feedback-v2` añade la diferencia firmada de inclinación
2D entre los vectores centro de caderas → centro de hombros, envuelta a ±180°.
El umbral inicial es 15°; se compara con el maestro, no con una vertical ideal.
No se infiere flexión hacia delante/atrás ni dirección anatómica de corrección.
El mismo control de persistencia/histéresis/cooldown rige los avisos de torso.
Cada `FeedbackCue` lleva un conjunto inmutable de articulaciones a resaltar:
tripleta de codo/rodilla, muñeca, tobillos o cuatro puntos del torso.
El panel envía solo los puntos del aviso activo hasta `PoseOverlayPainter`, que
agrega aros amarillos con contorno oscuro usando la proyección existente.
Se mantienen los colores anatómicos y la transformación de espejo. Los puntos
ausentes o filtrados no se resaltan; quality gate inválido, expiración del aviso
y encuadre incompatible retiran el resaltado. Cambiar el conjunto fuerza repintado
aunque el objeto pose siga siendo el mismo.

El overlay vive en presentación, dentro del viewport de `CameraPreview`. Aplica
espejo frontal sin cambiar joints anatómicos, omite puntos fuera de imagen o con
confianza inferior a 0.5 y no conecta extremos ausentes. Se retira al rotar,
pausar o cumplir 500 ms sin resultados. Estos umbrales visuales no son el quality
gate. Si difieren las proporciones de preview/análisis, se oculta el dibujo y
se informa: falta calibrar el recorte real en dispositivo. La alineación física
y el benchmark siguen pendientes.

No hay dependencia de Gemini ni de otros servicios generativos para entrenar.
Un futuro resumen narrativo consumirá evidencia estructurada desde Django con
credenciales del servidor, fuera del loop de scoring (sección 43 del plan).

### Fase 2 · Paso 1: geometría corporal

`pose/body_features.dart` usa únicamente Dart y `PoseFrame`. `PoseNormalizer`
resta el centro de caderas y divide por la distancia al centro de hombros,
después de restaurar la proporción ancho/alto. Requiere ambas caderas y hombros
en imagen, con confianza >= 0.5 y escala finita > 1e-6. Rechaza geometría
degenerada, conserva lados anatómicos e inclinación del torso, y no modifica
los landmarks usados por el overlay. Su salida es `body-normalized-v1`.

`BodyFeatureExtractor` produce `body-features-v1` con seis ángulos 2D de
0 a 180 grados: hombro-codo-muñeca, codo-hombro-cadera y cadera-rodilla-tobillo,
en ambos lados. Los puntos ausentes, fuera de imagen o poco confiables y los
segmentos de longitud cero dejan la medida ausente. Un 0° real sí es válido.
No son ángulos clínicos 3D ni un score. No se rota artificialmente el torso a
vertical: se conserva esa información para comparar inclinación más adelante.

Los tests prueban invariancia sintética a traslación, escala uniforme y cambio
de proporción de imagen con tolerancia 1e-9. Esto no garantiza invariancia entre
personas con proporciones corporales distintas ni ante perspectiva/oclusión.
El incremento siguiente agrega calibración de estabilidad y suavizado descritos
abajo. La validación de precisión física sigue pendiente.

### Fase 2 · Paso 2: calidad, calibración y suavizado

`pose/pose_measurements.dart` procesa cada nueva pose una sola vez, fuera del
build de widgets. `PoseQualityGate` exige nariz, hombros, codos, muñecas,
caderas, rodillas y tobillos (13 puntos), confianza individual >= 0.6, puntos
en imagen y seis ángulos no degenerados. Una pose inválida no entrega medidas.
Los márgenes < 2 % sugieren alejarse; altura corporal < 40 % o torso < 8 % de
la altura de imagen sugieren acercarse. Son heurísticas de encuadre, no distancia
en metros, identidad de persona ni garantía de cuerpo completo.

La calibración requiere >= 1000 ms y >= 8 muestras consecutivas válidas. El
centro de caderas puede variar hasta 0.03 alturas de imagen por eje y la escala
del torso hasta 10 % respecto a la primera muestra de la ventana. Guarda la
escala media como referencia local de encuadre; no sustituye la normalización
por frame ni corrige perspectiva, proporciones anatómicas o cámara intrínseca.
No comprueba automáticamente que la persona mire de frente.

Los ángulos usan EMA temporal con tau=150 ms. Solo procesa medidas válidas
actuales; nunca rellena ausencias. Se reinicia calibración/filtro ante calidad
inválida, intervalo > 500 ms, cambio de proporción, pausa, rotación, cámara nueva
o recalibración manual. Timestamps duplicados o atrasados se ignoran. Esta
política es conservadora y requiere ajuste físico para baile con oclusiones.

ML Kit no proporciona conteo fiable de personas: `MULTIPLE_PEOPLE` no se
fabrica y continúa sin soporte. La Fase 2 no está validada en teléfono.

## Fase 6 · Paso 1: resumen persistente e historial local

`SavedSession` congela UUID v4, nombre de rutina, metadatos de referencia,
fechas UTC y `SessionSummary`, incluidas versiones de scoring, resumen y feedback.
Se preservan null, cero real, cobertura y segmentos. `SessionStore` valida el
esquema `local-session-v1`, rangos y coherencia de los segmentos al guardar/leer;
escribe con flush en un temporal y rename en el mismo volumen. Reintentar el
mismo UUID/contenido es idempotente; un contenido diferente produce error.

Los archivos privados `sessions-v1/<SHA-256 de servidor|cuenta>/` son independientes
de referencias/videos descargados. Límite de 256 KiB por resumen y 32 MiB por
cuenta/servidor, sin borrado automático. Se informa de archivos dañados o
incompatibles y se conservan los demás. La UI permite consultar y eliminar cada
práctica con confirmación. Tras reiniciar se necesita login online otra vez.

Cada nuevo aviso mostrado por `LiveFeedback` incrementa el agregado por código,
con región, mensaje y severidad máxima. Se deduplica por código/intervalo de
100 ms del video y solo se cuenta si existe comparación válida. El ranking
ordena por cantidad y desempata por código; muestra los tres primeros. Cuenta
avisos emitidos tras persistencia, no todas las desviaciones ni duración del error.
Pausas, histéresis y cooldown siguen afectando qué avisos llegan a mostrarse.

Finalizar manualmente, fin/error del video o volver atrás congela y guarda la
práctica. Volver atrás primero muestra el resumen; después se puede salir.
Mientras se guarda no se puede salir ni repetir; si falla se mantiene el resumen
con reintento y salida explícita sin guardar. Un cierre forzado del proceso antes
del guardado no recupera la práctica en curso. No se persisten frames, poses ni
tokens, ni se realizan peticiones de sincronización en este incremento.

## Operación y comprobaciones

Django Admin permite gestionar rutinas, generar versiones de referencia y consultar
referencias/sesiones. La generación de archivo/checksum y reintentos ya usan el
preprocesador de Fase 3; las referencias son de solo lectura en Admin.

Swagger se genera de los serializers. La CI valida backend con SQLite y Flutter
sin cámara. El uso de PostgreSQL, Redis y permisos/rendimiento móvil debe
verificarse además en el entorno integrado y en teléfono físico.
