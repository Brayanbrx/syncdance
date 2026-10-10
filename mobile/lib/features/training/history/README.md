# Fase 6 · Paso 1 — resumen persistente e historial local

Implementado el 2026-10-05. Acceso: **Inicio → Historial de prácticas**.

Cada práctica finalizada guarda UUID v4, fechas UTC, nombre de rutina, metadatos
de referencia, versiones de algoritmos, similitud, cobertura, componentes,
segmentos y conteos de avisos. No guarda imágenes, poses por frame ni tokens.
Los valores sin evidencia siguen siendo null; cero real se conserva.

El ranking muestra los tres avisos más frecuentes realmente emitidos por
`LiveFeedback`, después de persistencia, prioridad y cooldown. Cada código se
cuenta como máximo una vez por intervalo de 100 ms del video para evitar contar
de nuevo el mismo intervalo al repetirlo. No mide duración del error ni representa
todas las desviaciones; ausencia de avisos no certifica ejecución correcta.

Los archivos `local-session-v1` están en el directorio privado de soporte de la
app, bajo `sessions-v1/<hash de servidor|cuenta>`. Son independientes de los
videos y referencias descargados. Se valida al escribir y al leer, con límite
de 256 KiB por archivo y 32 MiB por cuenta/servidor. La publicación usa temporal,
flush y rename. El mismo UUID/contenido se puede reintentar sin duplicados.
Los archivos ilegibles se reportan sin ocultar el resto ni eliminarlos.

Finalizar, alcanzar el fin/error del video o volver atrás durante la práctica
congela el resultado y lo guarda. Volver atrás muestra primero el resumen; se
sale con otra pulsación cuando termina el guardado. Mientras se escribe no se
puede repetir ni salir. Si falla, se permite reintentar o salir sin guardar.
Un cierre forzado antes del guardado puede perder la práctica en curso.

El historial lista prácticas recientes con cobertura y permite abrir detalles
y eliminar un resumen con confirmación. Funciona sin red con la cuenta ya
autenticada. Los archivos sobreviven al reinicio y, desde el paso 2, la sesión
guardada reabre el historial sin red.

## Verificación

Resultado del incremento: 154 pruebas Flutter aprobadas, formato aplicado y
`flutter analyze` sin incidencias. No se instaló ni validó en teléfono.

Pruebas de archivo real: reapertura, orden, null/cero, metadatos/versiones,
separación de cuenta/servidor, reintentos, UUID conflictivo, eliminación,
corrupción, archivos grandes y validación de evidencia/segmentos.
Pruebas de widgets: finalización manual/automática, guardado fallido y reintento,
bloqueo de salida durante escritura, historial sin red, detalle y eliminación.
El ranking se prueba con evidencia válida, deduplicación y cierre inmutable.
No sustituyen validación en teléfono.

Prueba manual pendiente:

1. Ingresar, abrir un maestro descargado y practicar hasta finalizar.
2. Comprobar mensaje de guardado y abrir Inicio → Historial de prácticas.
3. Revisar similitud, cobertura, segmentos y avisos; una práctica sin evidencia
   debe mostrar `—`, y ninguna corrección registrada no equivale a score perfecto.
4. Reiniciar la aplicación, ingresar con la misma cuenta y abrir el resumen.
5. Desconectar la red dentro de la sesión; consultar y eliminar un resumen.
6. Cambiar de cuenta o servidor y comprobar separación del historial.
7. Volver atrás durante práctica y esperar guardado antes de salir.

## Fase 6 · Paso 2 — sincronización con Django (implementado)

Implementado el 2026-10-09. `SessionSync` es una cola offline sobre el mismo
historial local. No usa red durante la práctica.

- Se ejecuta al guardar una práctica y al abrir el historial; el botón
  **Sincronizar ahora** la repite. Una sola ejecución por cuenta/servidor.
- Envía los pendientes del más antiguo al más reciente con
  `SavedSession.toUpload()`; el contrato está en `backend/apps/training/README.md`.
  En `pose-window-v1` el score global es solo de pose y `timing_score` es null.
- 201 o 200 (ya guardada, idempotente por UUID) → marcador `synced`.
- 400/403/404/409 → marcador `rejected` con motivo; no se reintenta solo. El
  detalle ofrece **Volver a intentar el envío**.
- Sin red, 5xx o sesión caducada → la cola se detiene y todo queda pendiente.
  Un 401 renueva el token una vez y reintenta.
- El estado vive en `<uuid>.sync` (`session-sync-v1`) junto al resumen, con
  escritura temporal y rename. Un marcador ilegible cuenta como pendiente; volver
  a enviarlo es seguro porque el servidor es idempotente. Eliminar una práctica
  local no la elimina del servidor.

Contrato compartido: `mobile/test/fixtures/sessions/upload_v1.json` se genera
con `toUpload()`. Dart comprueba que coincide y Django la publica y espera 201,
incluido un score 0 real con evidencia (no null).

Validación automatizada: orden de envío, idempotencia, rechazo sin reintento,
reintento manual, cortes de red, 5xx, renovación tras 401, ejecuciones
concurrentes, marcadores corruptos y estados en la pantalla de historial.

Prueba manual pendiente: practicar sin red, comprobar **Pendiente de enviar**,
reconectar, abrir el historial y verificar la sesión en Django Admin
(tramos y avisos). Repetir el envío y confirmar que no se duplica.

Siguiente: mejor marca y tendencia por rutina con criterios comparables de
referencia, algoritmos y cobertura. La Fase 6 todavía no está cerrada.
