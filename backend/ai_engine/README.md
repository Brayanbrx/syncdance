# Motor offline

Paquete de preprocesamiento de referencias y futuro análisis profundo
posterior. El loop live y su scoring se ejecutan en Flutter.

- `playback/`: versión del video maestro para la app (`app-video-v1`) y su
  miniatura; la referencia se calcula sobre ese archivo.
- `pose/`: extracción de landmarks de videos maestros/offline.
- `features/`: normalización y características canónicas de referencia.
- `alignment/`: alineamiento temporal y DTW offline.
- `scoring/`: análisis determinista posterior.
- `voice/`: canto. Referencia de melodía de la voz del instructor
  (`pitch-reference-v1`) y calificación de una grabación contra ella. Ver
  [voice/README.md](voice/README.md).

Las funciones matemáticas no importan modelos Django. `features/body.py` replica
la normalización y seis ángulos de Flutter; `pose/reference.py` procesa video con
FFmpeg/OpenCV/MediaPipe y genera `motion-features-v1` comprimido, con procedencia.
Ver [pipeline y pruebas](../apps/routines/README.md).

La tarea heredada de `performances` devuelve valores fijos únicamente
como prueba del flujo Celery; no sirve para evaluar movimiento real.
