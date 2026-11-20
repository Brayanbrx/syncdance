# Fase 4 · Pasos 2–4 — comparación de pose y resumen

Incrementos del 2026-10-02. Similitud y resumen experimentales; no cierran la Fase 4.

## Uso

Ingresar → Rutinas → referencia guardada → Abrir maestro → descargar video si
falta → **Practicar con cámara**. Calibrar quieto con el maestro pausado y pulsar
**Reproducir**. La cámara frontal, overlay y guía de encuadre reutilizan el flujo
Android ML Kit. Seguir los mismos lados anatómicos del maestro; el espejo de
preview no intercambia izquierda y derecha al comparar.

Se muestran similitud de pose 0–100, componentes de ángulos/posiciones y diferencias
medias en grados y largos de torso. `—` significa
que no se puede comparar; no cuenta como cero. Pausar permite ver el maestro,
pero retira la similitud. **Finalizar práctica** libera captura e inferencia,
pausa el reproductor y muestra el resumen. Llegar al final también cierra la práctica.
**Repetir práctica** conserva el resumen anterior en el historial e inicia otra con el maestro
pausado en cero. Salir o pasar a segundo plano libera la cámara y pausa el video;
al regresar se recalibra y el video se reanuda manualmente.

No se graban ni suben imágenes. Con referencia y video descargados funciona sin
red durante la sesión; desde Fase 6, paso 2, la sesión guardada también reabre
la app sin red.

## Modo espejo (por defecto)

Quien sigue a un maestro filmado de frente lo imita como en un espejo: cuando el
maestro levanta su brazo izquierdo, el alumno levanta el derecho. Antes la app
exigía los mismos lados anatómicos y penalizaba ese gesto natural.

**Seguir como espejo** (activado por defecto) compara contra la imagen especular
del maestro: `mirrorReference` intercambia izquierda↔derecha en joints y ángulos
y niega x alrededor del punto medio de caderas. Los lados del alumno nunca
cambian: avisos y aros hablan de su propio cuerpo. Desactivarlo deja la
comparación de mismos lados, útil para un maestro filmado de espaldas.

El modo se guarda en el resumen (`local-session-v2`; los `v1` se leen como
`same-side`), se envía como `follow_mode` y forma parte de la base comparable
del progreso: prácticas en espejo y sin espejo nunca se comparan entre sí.
`follow_mode_test.dart` verifica que la imagen especular de una pose asimétrica
puntúa ~100 solo en modo espejo y que reflejar dos veces es la identidad.

## Modo aprender (cámara lenta)

**Velocidad 0,5× / 0,75× / 1×** reproduce al maestro más despacio para aprender
un paso; también sirve para mirarlo sin practicar. La comparación usa la
posición del video, así que la referencia sigue alineada a cualquier velocidad.
La ventana de ±200 ms del video equivale a más tiempo real, por eso una práctica
lenta es más fácil: guarda `playback_speed`, se envía al servidor y forma parte
de la base comparable del progreso (nunca se compara con 1×). La velocidad no
puede cambiar durante una práctica; el modo juego siempre va a 1×.

## Estructura

`LivePractice` (`live_practice.dart`) contiene el loop live sin widgets ni
plugins: reloj captura↔video, matcher, reglas, `LiveFeedback`, caducidad de
250 ms y alimentación de `SessionAccumulator`. `LiveComparisonPanel` solo
reenvía eventos de cámara y reproductor (si el video corre y su posición) y
dibuja el estado. La extracción no cambió el comportamiento: las pruebas de
widget existentes pasan sin modificaciones y `live_practice_test.dart` cubre el
loop de forma unitaria (pausa, calidad, generación de cámara, caducidad, aviso
persistente registrado en el resumen, reinicio de práctica y uso tras dispose).

## Algoritmo y reloj

- `CaptureVideoClock` registra la posición del video al recibir cada imagen,
  antes de enviar la inferencia. Después resuelve por `PoseFrame.timestampMs`;
  el tiempo de llegada de la inferencia no reemplaza el tiempo de captura.
- La posición es la última notificada por el reproductor más el tiempo
  transcurrido desde ese aviso, a la velocidad de reproducción
  (`pose-window-v2`). El reproductor avisa cada ~100 ms; en v1 cada imagen
  quedaba hasta 100 ms atrasada, la mitad de la ventana de búsqueda. Si la
  posición no cambia en más de 250 ms se rechaza. Una inferencia de más de 500 ms
  también se rechaza. La tabla está limitada a 64 registros sin buffers de imagen.
- Pausa, buffering, salto, background, cambios de cámara/orientación y reinicios
  de calibración invalidan asociaciones pendientes. Un resultado sin registro
  o duplicado no puede producir similitud. El valor mostrado vence a los 250 ms.
- Al terminar el video (`LivePractice.videoEnded`) no se asocian imágenes
  nuevas, pero las ya capturadas se resuelven si su pose llega en 500 ms. Así el
  último movimiento del juego no pierde sus últimos cuadros. Tras el final no
  se muestran avisos.
- Se requiere quality gate válido y calibración del alumno. Se comparan los seis
  ángulos sin EMA, puesto que la referencia también está sin suavizado. La EMA
  sigue disponible para mostrar las medidas locales de encuadre.
- El paso 2 introdujo `AngleMatcher`, versión `angle-window-v1`: exige seis ángulos finitos entre 0 y
  180° en el alumno y en la muestra actual del maestro. Busca el menor error
  medio absoluto en ±200 ms, sin saltar sobre huecos o muestras incompletas.
  En empate, elige la muestra más cercana en tiempo.
- Fórmula inicial: `clamp(100 * (1 - errorMedioEnGrados / 90), 0, 100)`.
  Todas las articulaciones pesan igual. El desplazamiento de la muestra elegida
  se conserva internamente; no representa una medición fiable de anticipación
  ni un score de timing.

## Paso 3 — acumulación y cobertura

`SessionAccumulator`, inicialmente `angular-summary-v1` y ahora `pose-summary-v1`, divide el tiempo del maestro
en intervalos de 100 ms y conserva la primera comparación válida de cada uno.
Un intervalo repetido no aumenta cobertura ni sustituye su score. Reproducir
de nuevo puede completar intervalos antes vacíos. No se guardan frames ni poses.

La similitud, componentes y errores medios ponderan la duración de los intervalos
evaluados, con el último recortado a la duración de la referencia. Así, recibir
más inferencias en un tramo no aumenta su peso. La cobertura divide esos
milisegundos entre la duración completa de la rutina, incluso al finalizar antes.
Es cobertura **estimada por muestreo**, no observación continua de esos 100 ms.
Calibración, saltos y pérdidas de calidad dejan intervalos vacíos; sin evidencia
el score es `null`, mostrado como `—`, mientras un cero medido se conserva.

El resumen muestra segundos evaluados, similitud, diferencia media, cobertura y
un detalle desplegable por segmentos de cinco segundos. Una cobertura incompleta
se señala como resultado parcial. Finalizar congela una instantánea inmutable
antes de cerrar la cámara; inferencias tardías no pueden cambiarla. Un error del
reproductor conserva el resultado parcial. Desde Fase 6, paso 1, el resumen se
guarda en el historial local y se sincroniza con Django (Fase 6, paso 2).

## Paso 4 — posiciones normalizadas y similitud conjunta

`MotionSample.normalized` conserva coordenadas inmutables del archivo ya generado
por Python. Se mantiene el contrato `body-normalized-v1`: centro de caderas como
origen, distancia entre centros de caderas y hombros como unidad y proporción de
imagen corregida. No cambia el formato de caché ni requiere otra descarga.

`PoseMatcher` (`pose-window-v2`; v2 solo cambia el reloj, ver arriba) exige
los seis ángulos y doce posiciones:
hombros, codos, muñecas, caderas, rodillas y tobillos de ambos lados. El maestro
debe tener calidad `SINGLE_PERSON`; el alumno sigue pasando por encuadre/calibración.
Las coordenadas conservan inclinación y nombres anatómicos. No se corrigen
rotaciones ni se intercambian lados para elevar la similitud.

Para cada muestra candidata se calculan:

- Ángulos: `clamp(100 * (1 - MAE_en_grados / 90), 0, 100)`.
- Posiciones: media de las doce distancias euclidianas 2D en largos de torso;
  similitud = `clamp(100 * (1 - distancia_media), 0, 100)`.
- Pose: media de ambos componentes, 50 % cada uno.

La búsqueda conserva ±200 ms y el desempate por cercanía, pero elige la mayor
similitud **conjunta**. Los componentes siempre proceden de la misma muestra.
Una posición ausente, no finita o una muestra ambigua detiene la búsqueda en
esa dirección; si la muestra actual está incompleta no se puntúa. No se sustituye
el resultado combinado por uno solo angular cuando faltan posiciones.

`pose-summary-v1` agrega las similitudes ya acotadas por intervalo; también
conserva las diferencias medias sin acotar y versiones de scoring/resumen.
Las métricas comparten evidencia y cobertura, y el detalle por tramos muestra
la similitud conjunta. No se mezclan resultados de la fórmula anterior.

La distancia de corte de un torso y los pesos iguales son hipótesis iniciales.
Las proporciones corporales, perspectiva y oclusiones pueden cambiar el resultado
entre personas. El score sigue siendo experimental; no representa precisión
biomecánica ni un score independiente de ritmo.

## Límites y validación física pendiente

128 pruebas Flutter aprobadas, formato correcto y análisis estático sin incidencias.
APK Android debug compilado; no se instaló ni validó en el teléfono.

Las pruebas sintéticas verifican orden relativo de similitud, ventana temporal,
huecos, lados anatómicos, límites y resultados obsoletos. El widget integrado usa
cámara/reproductor simulados para recorrer calibración, pausa, salto, recuperación,
buffering, caducidad y pérdida de calidad. Esto no mide precisión real ni latencia.
También se verifican ponderación temporal, intervalos repetidos, huecos, ausencia
de evidencia, cierre inmutable y finalización manual/automática con reinicio.
Las pruebas de posiciones comprueban concordancia Python/Dart, invariancia a
traslación/escala/proporción de imagen, sensibilidad a inclinación del torso,
lados anatómicos, selección de una muestra común y rechazo de coordenadas inválidas.

Todavía falta validación física del scorer. Fase 6, paso 1 añade persistencia e
historial local y su sincronización; ver `../history/README.md`.
No se aplican pesos por regiones. El primer feedback técnico de Fase 5 se
documenta en `../feedback/README.md` y usa la misma muestra elegida por el matcher.
El resultado de pose no certifica ejecución correcta, frontalidad o seguridad.
Desde `pose-measurements-v3` una pérdida breve de pose ya no exige recalibrar
(ver `../README.md`); los márgenes son provisionales hasta probarlos con baile
real.

Prueba manual Android pendiente: maestro corto de cuerpo completo, ejecución
similar y luego deliberadamente diferente; verificar que la primera puntúe mejor.
Probar pequeños adelantos/retrasos, ocultar brazos o piernas, salir del encuadre,
pausar/saltar con una inferencia pendiente, rotar y volver del background.
Confirmar ausencia de valores congelados, medir latencia/FPS con cámara y video
simultáneos y registrar consumo/temperatura. iOS sigue sin adaptador validado.
Finalizar a mitad del video, revisar cobertura parcial y repetir: el nuevo resumen
debe empezar vacío. Completar un video sin pose válida debe mostrar `—`, nunca cero.
Comparar los componentes al inclinar el torso manteniendo los ángulos articulares,
cambiar distancia a la cámara y seguir lados incorrectos. Registrar evidencia
antes de ajustar el peso 50/50 o la distancia de corte.

Continuación implementada: feedback técnico live y resaltado de Fase 5, pasos 1–2.
El criterio de salida de Fase 4 requiere la prueba física descrita arriba.
