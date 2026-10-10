# Entrenamiento live — registro de pasos

## Fase 0 — base preparada

Se crearon `PoseFrame`, `PoseLandmark`, 33 joints anatómicos y `PoseEstimator`.
El dominio de pose no importa tipos de cámara ni de un SDK de inferencia.
La fixture `test/fixtures/poses/partial_pose_v1.json` es sintética y prueba
orientación/joints ausentes; no certifica precisión de un motor.

## Fase 1 · Paso 1 — captura de cámara (implementado)

Fecha: 2026-10-01. Validación física parcial; continuación pospuesta por el usuario.

Logrado:

- Ruta `/training/camera`, accesible desde Inicio → Preparar cámara.
- Preview frontal y stream de imágenes en memoria con `camera` 0.12.1.
- Resolución inicial `medium`; Android NV21 (desde el paso 2) e iOS BGRA. Es una configuración
  de partida para medir, no una conclusión de rendimiento.
- Conteo de frames y frecuencia de captura actualizada una vez por segundo.
- Mensajes ante permisos denegados/restringidos, falta de cámara frontal,
  plataforma no soportada e interrupción nativa; botón de reintento.
- Transiciones serializadas: al ir a background se cierra la cámara, al volver
  se abre de nuevo. Las inicializaciones obsoletas no inician otro stream.
- Liberación al salir, incluso si la inicialización todavía estaba en curso.
- Audio desactivado; el manifiesto Android elimina permisos heredados de
  micrófono y escritura de archivos del plugin. No se graba ni sube video.
- Android mínimo API 24; iOS incluye el motivo del permiso de cámara.

Archivos principales:

- `camera/camera_capture.dart`: propietario de los recursos y métricas de captura.
- `presentation/camera_training_screen.dart`: preview y estados de recuperación.
- `pose/`: contrato independiente para el próximo adaptador.

Validación automatizada: el controlador se prueba contra una plataforma de
cámara simulada (permisos, selección frontal, stream, background/resume, cierre
durante inicio, interrupciones y ausencia de plugin). Las pruebas de widgets
verifican los mensajes y controles de recuperación. Ninguna de ellas sustituye
la prueba física de imagen, permisos nativos y rendimiento sostenido.

## Comprobar este paso en Android

1. Conectar el teléfono con depuración USB autorizada.
2. Desde `mobile/`, ejecutar `flutter devices` y luego `flutter run -d ID`.
   Alternativa: instalar `build/app/outputs/flutter-apk/app-debug.apk`.
3. Pulsar Continuar sin cuenta, luego Preparar cámara.
4. Aceptar el permiso. Comprobar preview frontal sin deformación y contador creciente.
5. Mantener 60 segundos, girar el teléfono y comprobar que la UI siga respondiendo.
6. Ir a Inicio del teléfono y volver: la captura debe reiniciarse. Sus contadores
   se reinician porque describen la captura actual, no una sesión de entrenamiento.
7. Volver atrás y abrir la cámara otra vez; no debe quedar ocupada.
8. Revocar el permiso en ajustes y probar denegación/reintento.
9. Repetir sin Internet: esta pantalla no usa Django ni servicios remotos.

Registrar modelo/sistema del teléfono, resolución efectiva, imágenes/s, duración,
rotación y resultado de background/reapertura. No presentar imágenes/s como FPS
de inferencia. La compilación iOS requiere macOS y todavía no está validada.

## Próximo paso

Continuar Fase 6 con sincronización de resúmenes, cola offline y reintentos con
Django. El paso 1 ya guarda resúmenes y avisos frecuentes y permite consultarlos
en Inicio → Historial de prácticas; ver `history/README.md`. Mejor marca y
tendencia por rutina también siguen pendientes.
Fase 5, pasos 1–2 muestra avisos geométricos de extremidades/torso y resalta
sus articulaciones, con persistencia y cooldown; ver `feedback/README.md`.
El feedback de ritmo necesita una métrica temporal validada.
La sesión conjunta, similitud de
ángulos y posiciones y resumen con cobertura estimada en memoria (Fase 4, pasos 2–4) están
implementados; ver `comparison/README.md`. La sincronización sigue pendiente.
La reproducción y consulta por tiempo están en `playback/README.md`, y la caché
en `../routines/reference/README.md`. El backend generador está documentado en
`backend/apps/routines/README.md` desde la raíz. La Fase 2 incluye normalización,
ángulos, quality gate inicial, calibración de estabilidad y suavizado. Cuando
se retomen las pruebas, validar espejo/overlay, registrar benchmark y ajustar
umbrales de encuadre y tolerancia al movimiento. Fases 1–2 conservan su validación
física pendiente; avanzar en desarrollo no certifica sus criterios de salida.

La preview puede espejarse; el dominio conserva lados anatómicos. `pose-v1` usa
coordenadas normalizadas, proporción de imagen corregida y timestamps monotónicos.
El matcher actual asocia el timestamp de captura a la última posición notificada
por el video. Su desfase físico y tolerancias aún requieren medición.

La Fase 1 se cierra únicamente con pose + overlay estables y benchmark real.
Normalización/ángulos corresponden a Fase 2; referencias a Fase 3; scoring y
feedback a Fases 4–5. La similitud actual es experimental y no cierra esa validación.

Documentación del plugin utilizada: https://pub.dev/packages/camera/versions/0.12.1

## Prueba física parcial del paso 1 — 2026-10-01

Equipo: Xiaomi 2311DRK48G, Android 16 / API 36. APK debug del paso 1, antes de
agregar ML Kit. Instalación y apertura correctas; denegar permiso muestra
recuperación y Reintentar vuelve a solicitarlo. Al concederlo se recibieron
imágenes de 720 × 480, con lecturas puntuales de 25.0 y 29.9 imágenes/s.

La medición sostenida se interrumpió por apagado automático de pantalla: no se
declara aprobada. Se agregó `wakelock_plus` 1.8.1, ligado a la vida de la captura,
con liberación al pausar/salir y pruebas automatizadas. Falta verificar esta
corrección físicamente. No se completaron rotación, reapertura ni prueba offline.
No se guardaron fotos/video ni se confirmó visualmente la orientación de imagen.
El usuario pidió continuar con el siguiente paso y retomar pruebas después.

## Prueba física de pose — 2026-10-10

Equipo: Xiaomi 2311DRK48G, Android 16 / API 36, APK debug.

**Fallo encontrado y corregido.** ML Kit no recibía ninguna imagen válida: el
detector se desactivaba en el primer frame con «El tamaño del buffer NV21 no es
válido». `camera_android_camerax` 0.7.5+1 (`planesToNV21`) reserva el array con
el tamaño del plano Y *con relleno* (stride 768 para 720 de ancho): llegaban
541 392 bytes en lugar de 518 400. Los primeros 518 400 forman un NV21 válido y
el resto queda en cero. `compactNv21` usa ese prefijo (o recompone Y + VU si el
plano Y se copió entero) y rechaza buffers cortos. El error del detector ahora se
registra en el log y el modo juego lo muestra en vez de quedarse esperando.
Las pruebas sintéticas no podían detectarlo: usaban buffers exactos.

Medido tras la corrección (sin persona en cuadro): 29,3 imágenes/s de captura,
77 ms por inferencia, 1 255 analizadas de 3 892 recibidas (~9–10 poses/s, en el
límite inferior del objetivo de 10–20). Falta repetirlo con una persona y con
video + cámara simultáneos.

## Fase 1 · Paso 2 — pose local Android (implementado)

Logrado:

- `MlKitPoseEstimator` implementa `PoseEstimator` con el puente comunitario
  `google_mlkit_pose_detection` 0.16.1, modelo base y modo stream.
- Captura NV21 empaquetada: validación de formato, plano y tamaño de buffer.
  CameraX 0.7.5+1 realiza su conversión nativa al solicitar NV21; no se reinterpretan
  bytes YUV420 arbitrarios. Se conserva la versión resuelta en el lockfile.
- Rotación Android compensada por sensor y orientación del dispositivo.
- Conversión a los 33 nombres de `Joint`, coordenadas normalizadas en el espacio
  corregido y proporción de imagen. El dominio no importa tipos ML Kit.
- `z` queda ausente hasta validar su escala. Joints no finitos se omiten; la
  ausencia de persona se expresa como lista vacía y confianza cero.
- Una inferencia en curso y separación mínima de 83 ms entre entradas; los
  frames ocupados/adelantados se descartan, no se encolan.
- Resultados obsoletos tras background, rotación o cierre se descartan.
  El detector se libera al pausar y se crea de nuevo al recibir imágenes válidas.
- Vista **Inicio → Detectar postura**: cantidad de landmarks, confianza media,
  tiempo del viaje de inferencia nativa y contadores de análisis/descarte.
- La confianza es la media de likelihoods finitos; no indica por sí sola cuerpo
  completo ni calidad biomecánica. ML Kit sigue una persona; no permite declarar
  con fiabilidad el estado MULTIPLE_PEOPLE del futuro quality gate.

Comprobaciones automáticas: análisis estático y formato sin incidencias, APK
debug Android compilado y 25 pruebas Flutter aprobadas; incluyen formato
NV21, cuatro orientaciones, mapeo de los 33 joints, ausencia de persona, una sola
inferencia, descarte al pausar/cerrar y errores nativos. La inferencia en estas
pruebas está simulada en el canal del plugin, no se mide precisión del modelo.

Este paso es Android-first. El mínimo de proyecto iOS es 15.5 por ML Kit, pero
no se ejecuta su adaptador de pose en iOS: falta validar orientación/formato y
compilar en macOS. La cámara aislada conserva su ruta anterior.

Pendiente al terminar el paso 2: prueba física del modelo, overlay, benchmark y ajuste del límite de
inferencia con datos medidos. No se implementó scoring, feedback ni normalización
corporal. El APK nuevo se generó localmente; no reemplaza el instalado en el
teléfono hasta retomar las pruebas.

Fuentes de integración:
- https://pub.dev/packages/google_mlkit_pose_detection/versions/0.16.1
- https://pub.dev/packages/google_mlkit_commons/versions/0.13.0
- https://pub.dev/packages/wakelock_plus/versions/1.8.1

## Fase 1 · Paso 3 — esqueleto sobre la cámara (implementado)

Logrado:

- `CameraPosePreview` coloca el dibujo en el mismo viewport que `CameraPreview`,
  respetando las bandas vacías al ajustar la imagen al espacio disponible.
- `PoseOverlayPainter` dibuja conexiones y puntos del modelo canónico. Espejo
  frontal solo en x de presentación; no cambia los nombres ni los datos de pose.
- Izquierda anatómica naranja, derecha celeste y conexiones centrales blancas.
  El botón del ojo permite mostrar/ocultar el esqueleto sin detener la inferencia.
- Se omiten puntos fuera de imagen o con confianza menor a 0.5; una conexión
  requiere ambos extremos válidos. Es un filtro visual, no un quality gate.
- La pose se retira al pausar, rotar, cambiar de cámara o cumplir 500 ms sin
  resultados nuevos. No se mantiene un esqueleto congelado como si estuviera vivo.
- Si la proporción de la imagen analizada difiere más de 3 % de la preview,
  se oculta el overlay con un aviso. No se inventa una transformación de recorte.

Validación: 34 pruebas Flutter aprobadas, análisis estático sin incidencias y
APK Android debug compilado. No se instaló esta versión en el teléfono.
Incluyen proyección espejo sin alterar anatomía, exclusión de puntos inválidos,
conexiones, viewport en las cuatro orientaciones, recortes incompatibles,
mostrar/ocultar, caducidad, rotación, pausa y salida de la pantalla.

Pendiente en teléfono: comprobar que el esqueleto coincide con la imagen real,
especialmente mano izquierda/derecha, las cuatro orientaciones y los recortes
de CameraX. Las pruebas simuladas no certifican esa alineación ni la precisión.
La Fase 1 sigue abierta hasta completar el benchmark sostenido.

Prueba manual al retomarla:

1. Abrir Inicio → Detectar postura y mostrar el cuerpo entero.
2. Levantar solo la mano izquierda: sus puntos deben seguirla en naranja;
   repetir con la derecha (celeste), manteniendo la preview como espejo.
3. Girar a ambas posiciones horizontales y vertical invertida; comprobar que
   no queda un esqueleto anterior ni se dibuja fuera del área de cámara.
4. Salir del encuadre, volver, ocultar/mostrar el dibujo y pausar/reanudar.
5. Si aparece aviso de encuadre incompatible, registrar tamaños de preview y
   análisis antes de ajustar la selección de resolución o calibrar el recorte.
6. Completar las mediciones de rendimiento y la prueba sin Internet.

La detección de pose no necesita claves de Gemini ni otra IA remota. Un futuro
LLM sería opcional para narrar el resumen medido, invocado desde Django.

## Fase 2 · Paso 1 — normalización y seis ángulos (implementado)

Logrado:

- `PoseNormalizer`: centro de caderas como origen y distancia entre centros de
  caderas/hombros como escala. Primero recupera la proporción real x/y de la
  imagen para evitar distorsión geométrica.
- Salida inmutable `NormalizedPose`, separada de las coordenadas del overlay,
  con timestamp, nombres anatómicos y confianza por punto. No utiliza z ni
  necesita Flutter, cámara, ML Kit o conexión de red para el cálculo.
- Se conservan inclinación y lados anatómicos. No se aplica de nuevo el espejo
  frontal. Los puntos fuera de imagen o con confianza < 0.5 se excluyen.
- `BodyFeatureExtractor`: codos (hombro-codo-muñeca), hombros
  (codo-hombro-cadera) y rodillas (cadera-rodilla-tobillo), izquierda y derecha.
  Ángulos proyectados de 0 a 180 grados; los segmentos degenerados se omiten.
- Sin ambas caderas y hombros válidos no se normaliza ni se calculan ángulos.
  Si falta una muñeca, solo se pierde la medida que depende de ella. Ausente
  es `—` en la UI; un ángulo real de cero se conserva como 0°.
- Detectar postura muestra las medidas 2D. La UI distribuye cámara y medidas
  en horizontal o vertical, con desplazamiento para diagnósticos largos.
- Versiones locales `body-normalized-v1` y `body-features-v1`; todavía no se
  exportan como artefacto de referencia ni se envían al backend.

Validación con fixture sintética `test/fixtures/poses/body_angles_v1.json`:
geometría conocida (0°, 45°, 90°, 180°), escala, traslación, cambio de proporción
de imagen, rotación, reflejo sin intercambio anatómico, puntos faltantes o poco
confiables y geometría degenerada. Tolerancia de invariancia numérica: 1e-9.
La suite incluye comprobaciones de panel y caducidad de medidas en pantalla.
Resultado: 47 pruebas Flutter aprobadas, formato y análisis estático sin
incidencias, APK Android debug compilado. No se instaló ni probó en el teléfono.

Limitaciones: esta invariancia se prueba para una transformación uniforme de la
misma geometría. No certifica precisión en humanos, perspectiva ni comparación
entre cuerpos de proporciones diferentes. El filtro de puntos no reemplaza un
quality gate completo. Calibración, suavizado y mensajes de encuadre son el
siguiente paso; scoring/comparación con referencia siguen en fases posteriores.

## Fase 2 · Paso 2 — encuadre, calibración y suavizado (implementado)

Logrado:

- `PoseQualityGate`: ausencia de persona, cuerpo incompleto, baja confianza,
  poco margen y cuerpo pequeño en imagen, además de geometría utilizable.
  La pantalla ofrece indicaciones de encuadre; nunca produce un score.
- Requiere 13 puntos principales con confianza >= 0.6 y seis ángulos válidos.
  Puntos fuera de imagen impiden medir; margen < 2 % sugiere alejarse, altura
  corporal < 40 % o torso < 8 % de la altura de imagen sugiere acercarse.
- `PoseMeasurementProcessor`: una evaluación por muestra, no por reconstrucción
  de pantalla; rechazo de timestamps duplicados o atrasados.
- Calibración inicial con >= 1000 ms y >= 8 muestras válidas y estables.
  Centro de caderas: variación máxima 0.03 alturas de imagen por eje; torso:
  variación máxima 10 % frente al inicio de la ventana. Movimiento mayor reinicia
  la espera. Se guarda escala media del torso como referencia local del encuadre.
- `AngleSmoother`: EMA con constante temporal 150 ms, independiente de frecuencia
  para entradas constantes. Suaviza los seis ángulos, no la imagen ni el esqueleto.
  No completa puntos ausentes ni transforma un dato inválido en válido.
- Se retiran medidas y se reinician filtro/calibración ante mala calidad,
  hueco > 500 ms, cambio de proporción, pausa, giro, cámara nueva o petición manual.
- **Recalibrar encuadre** permite reiniciar después de la calibración inicial.
  El overlay puede seguir mostrando puntos parciales aunque no haya medidas.

Validación: 57 pruebas Flutter aprobadas, análisis estático y formato correctos,
APK Android debug compilado. Esta versión no se instaló en el teléfono.
Se comprueban estados de calidad, rechazo de geometría degenerada, tiempos y
cantidad de muestras, movimiento durante calibración, pérdida de pose, gaps,
reset, EMA temporal, ausencia de datos, UI de guía y recalibración integrada.

Límites: estos umbrales no están ajustados con el teléfono. La calibración es de
estabilidad/encuadre, no una calibración intrínseca de cámara o biométrica; no
comprueba frontalidad. Recalibrar tras una oclusión breve es deliberadamente
conservador y se debe revisar con baile real. ML Kit no permite confirmar
`MULTIPLE_PEOPLE`: no se simula ese estado. No se cierra aún la Fase 2.

Prueba manual pendiente: cuerpo completo/recortado, cerca/lejos, iluminación,
posición estable y movimiento durante espera, flexiones rápidas y lentas,
salir/entrar al encuadre, giro, pausa/reanudación y recalibración. Registrar
falsos rechazos, tiempo de recuperación y retardo visible del suavizado.
