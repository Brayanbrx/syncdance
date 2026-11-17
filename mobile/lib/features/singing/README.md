# Cantar

La segunda sección de la app, junto a Bailar. Comparte la cuenta, los cursos y
el almacenamiento por cuenta. Sigue el mismo diseño que el baile: el servidor
prepara la referencia una vez y la práctica corre en el teléfono, sin red.

```text
micrófono (record, PCM 16 kHz) -> PcmPitchTracker -> YIN -> PitchSample
   -> VocalPractice (guía - latencia, octava libre) -> aviso en vivo + resumen
guía (.m4a, video_player) -> PlaybackClock ----------^
```

## Qué se logró

| Archivo | Qué hace |
|---|---|
| `pitch/yin.dart` | Detector YIN en Dart puro. Ventana de 1024 muestras más el período más largo, 65–1100 Hz |
| `pitch/pitch_source.dart` | Contrato `PitchSource` y `PcmPitchTracker` (PCM → una muestra cada 32 ms, buffer circular) |
| `pitch/adapters/record_pitch_source.dart` | Único archivo que conoce el plugin `record`. Sin cancelación de eco, supresión de ruido ni ganancia automática; fuente `voiceRecognition`; Bluetooth sin tocar |
| `reference/pitch_reference.dart` | `pitch-reference-v1`: SHA-256 sobre el gzip antes de expandir, límites de tamaño, todas las versiones y el hash del audio |
| `reference/voice_store.dart` | Melodía y audio por cuenta y servidor, verificados por hash al leer, e historial local (`vocal-summary-v1`, 200 prácticas) |
| `practice/vocal_practice.dart` | Compara contra la nota de la guía en ese momento, avisos sin parpadeo y resumen por nota |
| `practice/playback_clock.dart` | Posición de la guía entre los reportes del reproductor |
| `presentation/` | Lista «Cantar», preparación (audífonos, volumen), rollo de notas en vivo y resumen |

## Reglas

- **La voz no sale del teléfono:** no se graba a un archivo ni se envía. Solo
  queda en el teléfono un resumen.
- **El micrófono se cierra** al terminar y al pasar a segundo plano.
- **Cualquier octava vale:** cada muestra se lleva a la octava de la nota
  esperada.
- **Ausente ≠ cero:**
  - una nota sin voz baja las «notas cantadas», nunca la afinación
  - si la práctica se cortó antes de una nota, esa nota queda sin evidencia
  - sin voz en toda la práctica no hay puntaje (`—`)
- **Se compara contra la guía en su posición menos la latencia.** No se estira
  el tiempo para buscar una coincidencia.

## Umbrales provisionales

Valen hasta validarlos con cantantes reales y viajan con `vocal-summary-v1`:

- **Afinación:** 50 cents. Se mide en el 60 % central de cada nota, con la
  media sin el 10 % de los extremos. Para contar una nota como cantada, debe
  haber voz en la mitad de ese tramo. Son las mismas reglas que en el servidor
  (`backend/ai_engine/voice/evaluate.py`).
- **Latencia:** 120 ms con cable y 300 ms con Bluetooth.
- **Aviso:** mediana de 5 muestras; cambia tras 3 muestras seguidas.

## Validación automatizada

- **Detector:** `test/features/singing/pitch_test.dart` (YIN en todo el rango,
  octavas, silencio y ruido, PCM partido).
- **Referencia:** `pitch_reference_test.dart`, con la fixture compartida
  `test/fixtures/references/pitch_reference_v1.*`. La escribe Python, y
  `backend/ai_engine/tests/test_voice.py` comprueba que siga igual.
- **Práctica:** `vocal_practice_test.dart` (melodía, octava, nota equivocada,
  notas sin cantar, corte temprano, latencia, aviso estable y reloj).
- **Pantallas:** `singing_screens_test.dart` (práctica con micrófono y
  reproductor falsos, permiso negado, lista y descarga única, disco e
  historial).

## Prueba física pendiente

- Latencia real con cable y Bluetooth en 2–3 teléfonos, y si hace falta
  calibrarla por equipo.
- CPU y batería del YIN en un teléfono de gama baja: puede necesitar un
  isolate.
- Voces reales (hombre, mujer, niño) con los ejercicios y con una canción
  subida por un instructor.

## Límites

- **El resumen queda en el teléfono:** subirlo y verlo en el estudio es C5 del
  plan de canto.
- **Sin audífonos** el micrófono oye la guía. La app lo advierte; no lo
  impide.
