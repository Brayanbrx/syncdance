# Protocolo de validación física

Las pruebas automáticas usan cámara, reproductor y servidor simulados: no
certifican precisión, latencia ni alineación real. Ninguna fase se cierra hasta
completar su bloque en un teléfono Android y registrar la evidencia.

Hacer los bloques en orden. Si un bloque falla, corregir y repetir ese bloque
antes de seguir: los siguientes dependen de él.

## Preparación (una vez)

**Servidor** (desde la raíz):

```powershell
docker compose up --build backend celery celery-beat
docker compose exec backend python manage.py createsuperuser
```

En Django Admin crear un alumno y una rutina con un **maestro controlado**:
20–30 s, una sola persona, cuerpo completo, de frente, buena luz, fondo simple
y movimientos claros de brazos y piernas. Esperar la referencia `READY`.

**Teléfono** (Android 7 o superior, misma red Wi-Fi que el PC):

```powershell
cd mobile
flutter run --profile --dart-define=API_BASE_URL=http://<IP-del-PC>:8000/api
```

Añadir esa IP a `DJANGO_ALLOWED_HOSTS`. Usar `--profile` para medir
rendimiento; `debug` es más lento y no sirve para el benchmark.

**Espacio:** teléfono fijo en trípode a la altura de la cadera, 2–3 m de
distancia, todo el cuerpo visible y la misma luz en todas las pruebas.

## Registro

Copiar esta tabla por bloque en el README de la feature correspondiente:

| Fecha | Teléfono / Android | Modo | Prueba | Resultado | Evidencia (valor medido o captura) |
|---|---|---|---|---|---|

Anotar valores medidos, no impresiones. Si algo falla, anotar qué se vio y en
qué segundo.

## Fase 1 — cámara y pose

Inicio → **Detectar postura**.

1. 60 s continuos con el cuerpo completo: la UI no se congela y la pantalla no
   se apaga. Registrar imágenes/s de captura, tiempo de inferencia y frames
   descartados al inicio y al final. Las imágenes/s no son FPS de inferencia.
2. Levantar solo la mano izquierda: los puntos naranjas la siguen. Repetir con
   la derecha (celeste). La preview se ve como espejo, pero los lados no cambian.
3. Girar a las cuatro orientaciones: no queda un esqueleto anterior ni se dibuja
   fuera del área de cámara.
4. Salir del encuadre y volver; ocultar y mostrar el esqueleto; ir al inicio del
   teléfono y regresar: la cámara se reabre sin quedar ocupada.
5. Repetir con el modo avión activado: esta pantalla no usa la red.

**Criterio de salida:** persona detectada de forma estable, 60 s sin bloqueo,
UI fluida y benchmark registrado.

## Fase 2 — calidad y normalización

Inicio → **Preparar cámara** / **Detectar postura**.

1. Recortar el cuerpo (salir parcialmente), acercarse y alejarse: el mensaje de
   encuadre debe pedir la corrección adecuada y no mostrar medidas.
2. Quedarse quieto: la calibración termina en 1–2 s. Moverse durante la espera:
   debe reiniciarse.
3. **La misma pose a tres distancias** (cerca, media, lejos): anotar los seis
   ángulos en cada una. Deben ser comparables; registrar la diferencia máxima.
4. Flexionar el codo y la rodilla despacio y rápido: anotar el retardo visible
   del suavizado.
5. Luz baja: registrar falsos rechazos y tiempo de recuperación.

**Criterio de salida:** la misma pose a distintas distancias da medidas dentro
de una tolerancia que se fija con estos datos.

## Fase 3 — referencia del maestro

1. Ingresar con el alumno → Rutinas → **Descargar referencia**: se guarda y
   verifica. Abrir maestro → **Descargar video y abrir**.
2. Activar el modo avión: la referencia y el video se abren desde la caché.
3. En Admin, reemplazar el video maestro: aparece una versión nueva y la
   anterior sigue disponible en el teléfono hasta descargar la nueva.

**Criterio de salida:** rutina publicada con video reproducible, referencia
`READY` y timeline descargable.

## Fase 4 — comparación

Grabar o ejecutar en vivo, con la misma rutina, este **set controlado**:

| # | Ejecución | Qué se espera |
|---|---|---|
| 1 | Muy similar al maestro | La similitud más alta del set |
| 2 | Brazos deliberadamente incorrectos | Menor que #1 |
| 3 | Piernas deliberadamente incorrectas | Menor que #1 |
| 4 | Movimiento correcto pero ~0,5 s atrasado | Menor o igual que #1; no se desploma |
| 5 | Igual, ~0,5 s adelantado | Igual que #4 |
| 6 | Salir del encuadre a mitad | Ese tramo queda sin evidencia (—), no en 0 |
| 7 | Demasiado cerca / demasiado lejos | No se puntúa hasta corregir |

Registrar similitud, cobertura y componentes (ángulos / posiciones) de cada una,
**tres repeticiones** por ejecución. Validar el **orden** (`#1 > #2`, `#1 > #3`),
no un número concreto.

**Criterio de salida:** una ejecución similar puntúa consistentemente mejor que
una incorrecta, los pequeños desfases no destruyen el score y no se puntúan
tramos sin detección.

## Fase 5 — feedback

1. Repetir #2 y #3 de la Fase 4: el aviso nombra la zona y el lado anatómico
   correctos, y los aros amarillos señalan esas articulaciones.
2. Cruzar un umbral muy despacio: el aviso no parpadea ni se contradice.
3. Pausar, saltar en el video o salir del encuadre: el aviso desaparece de
   inmediato.
4. Registrar falsos avisos (aviso con la ejecución correcta) por minuto.

**Criterio de salida:** mensajes que corresponden a métricas reales, sin
parpadeo ni contradicciones rápidas y con una acción concreta.

## Fase 6 — producto

1. Practicar hasta el final → resumen → **Repetir** → historial.
2. Cerrar la app por completo y reabrir **sin red**: abre Inicio con la cuenta y
   el historial se consulta.
3. Practicar sin red: en el historial aparece **Pendiente de enviar**.
   Reconectar y abrir el historial: pasa a **Sincronizada**. En Admin, la sesión
   tiene sus tramos y avisos. Pulsar **Sincronizar ahora** otra vez: no se
   duplica.
4. Tres prácticas de la misma rutina, una con mucha salida del encuadre (poca
   cobertura): el progreso muestra mejor marca y cambio, y excluye la de poca
   cobertura.
5. **Cambiar cuenta**: el historial de la otra cuenta no aparece.

**Criterio de salida (MVP):** login → rutina → entrenar → feedback → terminar →
resumen → repetir → historial, en el teléfono.

## Modo juego («Bailar»)

Rutinas → maestro → **Bailar (modo juego)**, con «Seguir como espejo» activado.

1. Colocarse sin tocar el teléfono: la cuenta 3-2-1 empieza sola. Salir del
   encuadre durante la cuenta debe cancelarla.
2. Bailar la rutina imitando al maestro como en un espejo: registrar estrellas,
   puntos y calificaciones. Repetir con los brazos abajo: menos puntos y MISS.
3. Salir del encuadre a mitad: aparece «Vuelve al encuadre» y esos movimientos
   quedan «sin medir», no MISS.
4. Registrar el retardo percibido entre el movimiento y su calificación, y si los
   textos se leen bien a 2–3 m.
5. Pictogramas: a 2–3 m, ¿se distingue la pose del siguiente movimiento antes
   de que llegue? Anotar si hace falta más tamaño o más anticipación.
6. Sonidos: la cuenta 3-2-1 y las calificaciones se oyen a 2–3 m **sin pausar
   ni cortar** la música del maestro; anotar si el volumen tapa la música.
7. En los resultados, **Practicar** un movimiento débil: el maestro repite ese
   tramo a 0,5× con carrerilla. Hacer varias pasadas (bien, mal, fuera de
   encuadre) y anotar si las calificaciones por pasada coinciden con lo bailado
   y si la carrerilla alcanza para entrar a tiempo.

## Cuentas, descargas e historial

1. **Crear cuenta de estudiante** desde el login: una contraseña débil
   (`12345678`) muestra el motivo bajo el campo; una válida entra sola a Inicio.
2. **Bailar** una rutina de Mixkit sin video guardado: se ve el porcentaje de
   descarga hasta 100 %.
3. Sin red: cerrar y reabrir la app; en Rutinas aparecen «Rutinas guardadas en
   este teléfono» con **Bailar**. Jugar una partida, volver a tener red,
   reabrir la app y comprobar en el Admin que la partida llegó (sin abrir el
   historial).
4. Reinstalar la app (o usar otro teléfono), entrar con la misma cuenta y usar
   **Traer prácticas del servidor**: vuelven las prácticas con sus estrellas.
5. En `http://<PC>:8000/admin/` con `admin` / `admin`: Sesiones de baile
   (filtro «Juego») y **Progreso por alumno** muestran las partidas.

## Después de validar

- Ajustar umbrales solo con los datos registrados: encuadre, calibración,
  tolerancias, peso 50/50, corte de posiciones, cobertura mínima del progreso
  y umbrales de feedback.
- Cada ajuste **sube la versión** de su componente (ver la skill
  `syncdance-pose`), para que los historiales anteriores sigan interpretándose.
- Actualizar el estado de cada fase en el `README.md` principal.
