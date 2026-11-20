# Cantar

La segunda sección de la app, junto a Bailar. Comparte la cuenta, los cursos y
el almacenamiento por cuenta. Sigue el mismo diseño que el baile: el servidor
prepara la referencia una vez y la práctica corre en el teléfono, sin red.

```text
micrófono (record, PCM 16 kHz) -> PcmPitchTracker -> YIN -> PitchSample
   -> VocalPractice -> aviso en vivo + aguja de cents + resumen por nota

«Escucha y repite» (por defecto, con o sin audífonos):
   guía suena una frase -> se calla -> turno del alumno (reloj de pantalla)
   el micrófono solo cuenta en el turno

«Con la guía» (solo con audífonos):
   primera nota sola + prueba de eco -> guía completa (PlaybackClock - latencia)
```

## Qué se logró

| Archivo | Qué hace |
|---|---|
| `pitch/yin.dart` | Detector YIN en Dart puro. Ventana de 1024 muestras más el período más largo, 65–1100 Hz |
| `pitch/pitch_source.dart` | Contrato `PitchSource` y `PcmPitchTracker` (PCM → una muestra cada 32 ms, buffer circular) |
| `pitch/adapters/record_pitch_source.dart` | Único archivo que conoce el plugin `record`. Sin cancelación de eco, supresión de ruido ni ganancia automática; fuente `voiceRecognition`; Bluetooth sin tocar. Una captura por fuente: `stop` libera la grabadora nativa, aunque nunca haya grabado |
| `pitch/adapters/audio_route.dart` | Dónde suena la guía (cable, Bluetooth, parlante) por el canal `ai.syncdance/audio_route` de `MainActivity` (`AudioManager.getDevices`). Si falla, «desconocida» |
| `reference/pitch_reference.dart` | `pitch-reference-v1`: SHA-256 sobre el gzip antes de expandir, límites de tamaño, todas las versiones y el hash del audio |
| `reference/voice_store.dart` | Melodía y audio por cuenta y servidor, verificados por hash al leer, e historial local (`vocal-summary-v2` con modo y velocidad; lee v1; 200 prácticas) |
| `practice/vocal_practice.dart` | Compara contra la nota esperada (con la guía o en un turno), avisos con persistencia e histéresis, puntaje por niveles y resumen |
| `practice/vocal_turns.dart` | Frases para «Escucha y repite» y turnos para practicar una nota sola |
| `practice/bleed_check.dart` | Si el micrófono oye la guía (su misma nota, en su misma octava) mientras el alumno calla |
| `practice/playback_clock.dart` | Posición de la guía entre los reportes del reproductor, a su velocidad |
| `presentation/` | Lista «Cantar», preparación (salida de audio, modo, velocidad, volumen), práctica, resumen, práctica de una nota y afinador |

## Por qué así

El micrófono no distingue la voz del alumno de la guía. La guía es un tono
limpio justo en la nota, así que si sale por el parlante el micrófono la oye y
un alumno callado sacaba 100 % (comprobado con el YIN real en
`bleed_check_test.dart`). Por eso:

- **«Escucha y repite» nunca mide mientras la guía suena.** La guía se silencia
  y se pausa al final de cada frase. El turno empieza con una cuenta en
  pantalla de al menos un segundo, para que el eco de la sala se apague.
- **«Con la guía» exige audífonos.** Lo revisa en Android antes de empezar y
  cada segundo durante la práctica; si se desconectan, la práctica se detiene.
  Antes de cantar suena la primera nota sola mientras el alumno calla: si el
  micrófono la oye (audífonos mal puestos o volumen alto), vuelve a la
  preparación sin guardar puntaje.

## Reglas

- **La voz no sale del teléfono:** no se graba a un archivo ni se envía. Solo
  queda en el teléfono un resumen.
- **El micrófono se cierra** al terminar y al pasar a segundo plano. Si la
  app pasa a segundo plano mientras se abre la guía, no se enciende.
- **Cualquier octava vale:** cada muestra se lleva a la octava de la nota
  esperada.
- **Ausente ≠ cero:**
  - una nota sin voz baja las «notas cantadas», nunca la afinación
  - si la práctica se cortó antes de una nota, esa nota queda sin evidencia
  - sin voz en toda la práctica no hay puntaje (`—`)
- **Se compara contra la nota de ese momento.** Con la guía, su posición
  menos la latencia; en un turno, el reloj de la pantalla menos la latencia
  del micrófono. No se estira el tiempo para buscar una coincidencia. En un
  turno solo cuentan las notas de esa frase.
- **Más lento no cambia las notas:** el reproductor baja la velocidad sin
  cambiar el tono (`PlaybackParameters(speed)` de ExoPlayer).
- **Se compara lo comparable:** el mejor puntaje de la lista solo usa
  prácticas con las reglas actuales y el mismo modo y velocidad que la última.
  La práctica de una nota no se guarda en el historial.

## Umbrales provisionales

Valen hasta validarlos con cantantes reales y viajan con `vocal-summary-v2`:

- **Afinación:**
  - afinada hasta 25 cents (cuenta entera), «casi» hasta 50 (cuenta la
    mitad) y desafinada más allá
  - se mide en el 60 % central de cada nota, con la media sin el 10 % de los
    extremos
  - para contar una nota como cantada, debe haber voz en la mitad de ese tramo
  - estas reglas por nota son las del servidor
    (`backend/ai_engine/voice/evaluate.py`). Su informe `voice-score-v1`
    todavía cuenta como afinado todo lo que está dentro de 50 cents; hay que
    alinearlo cuando se haga C7
- **Latencia:** 120 ms con cable, 300 ms con Bluetooth y 80 ms en un turno
  (solo micrófono). Se escala por la velocidad.
- **Aviso:**
  - mediana de 5 muestras
  - el primero de cada nota tras 4 muestras y cada cambio tras 8 (~250 ms)
  - 8 cents de histéresis en cada borde
  - se borra tras ~300 ms sin voz
- **Frases:** cortan en silencios de 350 ms o más; como máximo 5 notas o 6 s.
- **Práctica de una nota:** 3 intentos, cada uno sostenido al menos 1,6 s.
- **Prueba de eco:** la guía se considera oída si una cuarta parte de las
  muestras está a menos de 60 cents de su nota, en su octava.

## Validación automatizada

- **Detector:** `test/features/singing/pitch_test.dart` (YIN en todo el rango,
  octavas, silencio y ruido, PCM partido).
- **Fuga de la guía:** `bleed_check_test.dart`. La guía sintética pasa por el
  YIN real: por el parlante se detecta; una fuga leve de audífonos, una sala
  en silencio o un alumno una octava abajo no.
- **Referencia:** `pitch_reference_test.dart`, con la fixture compartida
  `test/fixtures/references/pitch_reference_v1.*`. La escribe Python, y
  `backend/ai_engine/tests/test_voice.py` comprueba que siga igual.
- **Práctica:** `vocal_practice_test.dart`:
  - melodía, octava y nota equivocada
  - niveles de afinación
  - notas sin cantar, corte temprano, latencia y velocidad
  - avisos (primero, desvío suelto, borde, cambio)
  - frases, turnos y práctica de una nota
  - reloj con velocidad
- **Pantallas:** `singing_screens_test.dart`:
  - con la guía, guía oída por el micrófono
  - sin audífonos, audífonos desconectados
  - escucha y repite con la guía saliendo por el parlante: un turno en
    silencio no puntúa
  - práctica de una nota y afinador
  - permiso negado, lista y descarga única, disco e historial (incluida la
    lectura de v1)

## Prueba física pendiente

- Latencia real con cable y Bluetooth en 2–3 teléfonos, y si hace falta
  calibrarla por equipo. También la latencia del micrófono en un turno.
- Que la prueba de eco detecte la fuga real de audífonos de botón a volumen
  alto, y que no salte con audífonos bien puestos.
- Que la detección de audífonos acierte con USB-C, Bluetooth y adaptadores.
- CPU y batería del YIN en un teléfono de gama baja: puede necesitar un
  isolate.
- Voces reales (hombre, mujer, niño) con los ejercicios y con una canción
  subida por un instructor, a 0,5×, 0,75× y 1×.

## Límites

- **El resumen queda en el teléfono:** subirlo y verlo en el estudio es C5 del
  plan de canto.
- **Con la guía**, si el alumno se quita los audífonos y los deja sonando
  cerca del teléfono sin desconectarlos, el micrófono puede volver a oír la
  guía. La prueba de eco solo se hace al empezar.
- **En un turno** no suena metrónomo: el alumno sigue las barras en pantalla.
- **Las frases** de una canción subida se cortan por silencios y largo; el
  instructor todavía no las marca.
