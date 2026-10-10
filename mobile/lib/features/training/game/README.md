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
   Sin textos de corrección: el juego no distrae mientras bailas.
4. **Resultados:** estrellas, puntos, conteo por calificación, combo máximo,
   porcentaje de la canción en que se te vio y movimientos para practicar.
   **Bailar otra vez** reinicia sin salir.

Volver atrás durante la canción o salir de la app termina la partida y la
guarda; no hay forma manos libres de reanudar.

## Calificación (`dance-game-v1`, provisional)

`DanceGame` consume la salida del scorer (`SessionAccumulator`); no cambia cómo
se comparan las poses.

- **Movimientos:** ventanas de 1 s donde el maestro es medible (al menos la mitad
  de sus muestras `SINGLE_PERSON` con seis ángulos). Una cola menor a 0,5 s se
  descarta.
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

## Persistencia

La partida se guarda como una práctica más (`local-session-v2`) con un bloque
`game` (versión, puntos, máximo, combo y conteos). El resumen técnico se
sincroniza con Django como siempre; el bloque `game` todavía no se sube.
En modo juego `LivePractice` corre con `coaching: false`: no evalúa avisos de
texto, así que el resumen no cuenta avisos que nunca se mostraron.

## Validación

`dance_game_test.dart`: movimientos, umbrales, combo, sin medir, cierre
diferido, estrellas, movimientos a practicar y JSON del resultado.
`dance_game_screen_test.dart` (cámara, estimador y reproductor simulados):
calibración, cuenta automática, PERFECT en vivo, resultados con estrellas y
guardado; salir del encuadre queda sin medir y nunca como MISS; alejarse
durante la cuenta la cancela.

Pendiente en teléfono: latencia percibida de las calificaciones, legibilidad a
2–3 m, umbrales con ejecuciones correctas e incorrectas y temperatura en una
canción completa.
