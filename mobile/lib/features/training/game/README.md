# Modo juego («Bailar»)

Experiencia tipo Just Dance sobre el mismo motor de comparación. Acceso:
Rutinas → referencia guardada → Abrir maestro (con video descargado) →
**Bailar (modo juego)**. Usa el modo espejo elegido en esa pantalla.

## Flujo manos libres

1. **Colocación:** la cámara pequeña guía el encuadre (cuerpo completo, luz,
   distancia). No hace falta tocar el teléfono.
2. **Cuenta 3-2-1:** empieza sola cuando el encuadre está calibrado; si sales
   del encuadre durante la cuenta, se cancela.
3. **Canción:** maestro grande, puntos, combo y calificación de cada movimiento.
   Sin textos de corrección: el juego no distrae mientras bailas. Encima del
   maestro, **pictogramas** de los tres movimientos siguientes (el inminente en
   ámbar); se ven también durante la colocación para anticipar el primero.
4. **Resultados:** estrellas, puntos, conteo por calificación, combo máximo,
   porcentaje de la canción en que se te vio y movimientos para practicar.
   **Bailar otra vez** reinicia sin salir.

Volver atrás durante la canción o salir de la app termina la partida y la
guarda; no hay forma manos libres de reanudar.

## Calificación (`dance-game-v2`, provisional)

`DanceGame` consume la salida del scorer (`SessionAccumulator`); no cambia cómo
se comparan las poses.

- **Movimientos al ritmo (v2):** si la referencia trae `scoring_profile.beat_grid`
  (las coreografías generadas del estándar), cada movimiento dura
  `beats_per_move` tiempos desde el primer «1», así que las calificaciones caen
  sobre la música y la entrada «5, 6, 7, 8» nunca se califica. Sin rejilla
  (videos de stock, tempo desconocido) se usan ventanas de 1 s desde el inicio.
  En ambos casos solo cuentan ventanas donde el maestro es medible (al menos la
  mitad de sus muestras `SINGLE_PERSON` con seis ángulos) y se descarta una cola
  menor a medio movimiento. Una rejilla mal formada se ignora; no impide la
  descarga.
- **Calificación:** similitud media de las comparaciones del movimiento.
  PERFECT ≥ 85 · GREAT ≥ 70 · GOOD ≥ 50 · MISS < 50. Puntos 100/75/50/0.
- **Sin medir:** con evidencia menor al 40 % del movimiento (fuera de encuadre o
  mala calidad) no hay calificación ni MISS: no suma puntos y el combo ni sigue
  ni se rompe. El resumen técnico tampoco cuenta ese tiempo como evidencia.
- **Combo:** sube con GOOD o mejor; MISS lo reinicia.
- **Estrellas:** proporción de puntos sobre el máximo de todos los movimientos
  (30/45/60/75/90 %). Exigen bailar visible; la similitud técnica nunca
  penaliza datos ausentes.
- **Cierre:** un movimiento se califica 400 ms después de terminar, para esperar
  la inferencia tardía.

Todos los umbrales son provisionales: se ajustan con el set controlado de
`mobile/VALIDACION_FISICA.md` y cada ajuste sube `DanceGame.version`.

## Pictogramas

Figuras de palitos dibujadas desde los puntos normalizados de la referencia
(`move_pictogram.dart`), sin assets ni red. Cada movimiento usa la muestra
`SINGLE_PERSON` más cercana al tiempo que abre el movimiento si hay rejilla de
tiempos (el entrenador generado llega a cada pose en el tiempo) o a su mitad si
no la hay; si el maestro no es dibujable dentro del movimiento, no hay
pictograma. Se dibujan como el maestro en el video, nunca reflejados: en modo
espejo el alumno los sigue igual que al entrenador. Un movimiento sale de la
tira en cuanto empieza.

## Persistencia

La partida se guarda como una práctica más (`local-session-v2`) con un bloque
`game` (versión, puntos, máximo, combo y conteos) y se sube con el resumen
(`GameResult` en Django, ver `backend/apps/training/README.md`). El servidor
aplica las mismas reglas que `GameSummary.fromJson` y devuelve las estrellas.

**Mejor marca:** `RoutineProgressCalculator` (v2) elige la partida con más
puntos entre las comparables con la última (misma referencia, versión del juego
y modo espejo). Se muestra en el historial («Modo juego: mejor ★★★★☆») y bajo
cada rutina del catálogo, como en la lista de canciones de un juego.
En modo juego `LivePractice` corre con `coaching: false`: no evalúa avisos de
texto, así que el resumen no cuenta avisos que nunca se mostraron.

## Validación

`dance_game_test.dart`: movimientos, umbrales, combo, sin medir, cierre
diferido, estrellas, movimientos a practicar y JSON del resultado.
`move_pictogram_test.dart`: pose clave con y sin rejilla, sin pictograma
cuando el maestro no es dibujable, y tira de próximos movimientos.
`dance_game_screen_test.dart` (cámara, estimador y reproductor simulados):
calibración, cuenta automática, PERFECT en vivo, pictogramas que avanzan con la
canción, resultados con estrellas y guardado; salir del encuadre queda sin medir y nunca como MISS; alejarse
durante la cuenta la cancela.

Pendiente en teléfono: latencia percibida de las calificaciones, legibilidad a
2–3 m (incluidos los pictogramas), umbrales con ejecuciones correctas e incorrectas y temperatura en una
canción completa.
