# Estándar SyncDance — coreografías generadas

Currículo de pasos básicos para aprender a bailar desde cero. Cada rutina se
define como **datos** (pasos de 8 tiempos, BPM y orden) y de ella se generan:

1. **Video del coach**: figura estilizada de un solo color (tipo pictograma de
   Just Dance) con el nombre del paso, el tiempo actual, puntos del compás,
   flechas de dirección y aviso del siguiente paso.
2. **Pista de ritmo** sintetizada al BPM: bombo en cada tiempo, palmas en
   2/4/6/8, hi-hat, bajo y acordes; clics de madera en la entrada «5, 6, 7, 8».
3. **Referencia exacta** `motion-features-v1`: los landmarks del modelo pasan por
   el mismo `extract_features` y `encode_reference` que los maestros de MediaPipe,
   sin ruido de detección. La entrada se marca `NO_USABLE_POSE` para que no
   puntúe.

Todo es contenido original: no hay licencias de terceros que verificar.

```powershell
docker compose exec backend python manage.py generate_standard_catalog
```

Idempotente por `catalog_key` (`estandar-<clave>`); `--only n1-marcha` genera
una sola rutina. Estas rutinas llevan `generator = syncdance-choreo-v1` y nunca
pasan por la detección de pose: la API, el admin y `queue_reference` lo impiden.

## Nivel 1 (`estandar-v1`, 104 BPM, principiante)

| Rutina | Pasos | Duración |
|---|---|---|
| Marcha con brazos | marcha + brazos en V/abajo alternos | 20,8 s |
| Step touch con palmada | paso lateral + palmada al frente | 20,8 s |
| Step touch con brazos en V | paso lateral + brazos en V | 20,8 s |
| Rodilla arriba | rodilla alterna + codos a los hombros | 20,8 s |
| Toque lateral | punta al lado + brazo abierto | 20,8 s |
| Primer baile | los cinco pasos encadenados, dos vueltas (80 tiempos) | 48,5 s |

Cada práctica: entrada de 4 tiempos + 4 frases de 8 tiempos.

## Decisiones

- **Siempre de frente y sin giros.** Los bailes en línea giran 90° por pared; de
  lado la cámara no compara bien. Se excluyen giros, mambo, body roll y curl de
  isquios (el talón queda oculto detrás de la pierna).
- **Lados en términos de pantalla.** «Derecha» es la derecha de la pantalla: la
  derecha del alumno en modo espejo y la izquierda anatómica del coach. La
  referencia guarda las etiquetas anatómicas del coach y el modo espejo del
  móvil la refleja.
- **Cuerpo 3D simple y proyección frontal.** Piernas por cinemática inversa desde
  la posición de los pies (no patinan; al abrir los pies baja la cadera como en
  una persona) y brazos por ángulos. Un *knee lift* se ve como lo vería un
  teléfono a 2–3 m.
- **Un solo color para el coach.** Los colores izquierda/derecha del esqueleto
  del alumno confundirían al seguirlo en espejo.
- **Textos ASCII en el video** (fuentes Hershey de OpenCV); los nombres con
  acentos están en la rutina.

## Vocabulario y fuentes

Los pasos son vocabulario común de clases de baile-fitness (marcha, step touch,
rodilla arriba, toque lateral, grapevine, V-step…), no coreografías protegidas.
Las combinaciones son originales. No se incluyen coreografías con titular, como
la Electric Slide (licencia CC no comercial con atribución a Ric Silver).

## Validación

`ai_engine/tests/test_choreography.py`: huesos de longitud constante, pies
apoyados que nunca flotan, derecha de pantalla = izquierda anatómica, brazos y
rodillas visibles en 2D, seis ángulos en toda muestra bailada, entrada sin
evaluar, referencia determinista, digest sensible a geometría y tempo, y render
real a H.264 + AAC cuando hay OpenCV. `apps/routines/tests/test_standard.py`:
instalación con referencia READY sin worker, idempotencia y bloqueo de la
detección de pose.

Pendiente en teléfono: comprobar con personas reales que seguir al coach en
espejo puntúa alto y equivocarse de lado puntúa bajo, y ajustar el BPM si 104
resulta rápido para principiantes. Siguientes niveles: grapevine, V-step,
box step y two-step.
