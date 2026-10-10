# Fase 4 · Paso 1 — maestro y reloj de referencia

Implementado el 2026-10-01. La continuación del 2026-10-02 añade cámara y similitud
experimental y resumen en memoria con cobertura en `../comparison/README.md`.
El paso 4 añade posiciones normalizadas. El benchmark conjunto sigue pendiente;
no se declara cerrada la Fase 4.

## Flujo

Ingresar → Rutinas → descargar referencia → tocar versión guardada →
**Abrir maestro → Descargar video y abrir**. Se descarga solo tras pulsar el
botón. Una copia válida se abre sin pedir red. Hay reproducción/pausa, barra para
saltar (queda en pausa), volver al inicio y eliminación del video local.
Al pasar a segundo plano se pausa; al regresar, el usuario reanuda manualmente.
Salir cancela una descarga en curso y libera el reproductor.

El video ocupa como máximo el 45 % de la altura de pantalla y conserva su
proporción. Los controles y medidas se pueden desplazar en pantallas pequeñas.
La información mostrada son ángulos del maestro, nunca un score del alumno.

## Identidad y persistencia

El endpoint autenticado `routines/{id}/references/{version}/video/` entrega la
fuente fijada en el READY, aunque se haya cambiado el maestro de la rutina.
`CatalogApi.video` usa un stream, límite de 200 MiB, timeout de cinco minutos,
cancelación y rechazo de redirecciones. No acumula el archivo entero en memoria.
`MasterVideoCache` escribe en temporal, comprueba `source_sha256` y renombra
solo al terminar correctamente. Revalida el hash al abrir una copia existente.
Una copia corrupta se elimina para permitir reintentar; una descarga fallida no
reemplaza versiones válidas.

Se mantienen archivos separados por rutina/versión/hash, dentro de la carpeta
de cuenta/servidor. La cuota de videos es 512 MiB por cuenta/servidor, además de
los 64 MiB de referencias. No hay borrado automático de otras versiones.
Eliminar una referencia elimina también su video. El usuario puede borrar solo
el video desde el reproductor y conservar la referencia técnica.

Los datos sobreviven al reinicio; la sesión JWT sigue solo en memoria. Después
de reiniciar hay que ingresar online para acceder de nuevo a las copias locales.

## Reloj y límites

`ReferenceTimeline.at` busca por timestamp con búsqueda binaria. Usa la posición
notificada por `VideoPlayerController`; no extrapola por un cronómetro Dart.
Pausar conserva la posición para inspección. Saltar vuelve a consultar la muestra;
los tramos sin ángulos no heredan valores anteriores. No se muestran medidas
durante buffering, búsqueda, background, fin o fuera de duración de referencia.

La duración nativa debe diferir como máximo 250 ms de la referencia a 12 Hz.
Es una comprobación inicial para detectar incompatibilidades, no una garantía
de sincronización por frame. La frecuencia de notificación y latencia del
reproductor deben medirse antes de puntuar. Las fuentes VFR, con metadatos de
rotación o audio más largo que el video requieren especial comprobación.

La reproducción depende de los codecs del dispositivo. Un archivo procesable
por FFmpeg puede no ser reproducible por el teléfono; se muestra un error y se
permite reintentar/eliminar. Usar un MP4 compatible en la prueba inicial.
Integración basada en [video_player 2.14.0](https://pub.dev/packages/video_player/versions/2.14.0)
y la [guía oficial de Flutter](https://docs.flutter.dev/cookbook/plugins/play-video).

## Validación y prueba pendiente

102 pruebas Flutter y 34 backend aprobadas; dos pruebas nativas opcionales
omitidas. Análisis estático y checks de Django/migraciones/esquema correctos.
APK Android debug compilado; no se instaló en el teléfono.
Los widgets usan un reproductor simulado: verifican posición, huecos, buffering,
pausa al salir, fin, duración incompatible y liberación durante inicialización.
Las pruebas de caché usan archivos reales y streams; el backend comprueba acceso,
fuente antigua tras reemplazo, READY requerido y archivo faltante.

En Android físico: publicar un maestro MP4, descargar referencia y video, comprobar
imagen/audio, reproducir/pausar/saltar y volver al inicio. Observar las medidas en
tramos válidos y sin pose, girar el dispositivo, pausar en background y reabrir.
Desconectar Internet y abrir otra vez desde la sesión. Borrar solo el video y
reintentar la descarga. Probar también una versión antigua tras cambiar el maestro.
Registrar desfase visible, duración, formato y dispositivo. iOS requiere macOS
y dispositivo para compilar/probar; no está validado aquí.

Continuación implementada: cámara y maestro en una sesión, captura de pose asociada
al reloj de video y primera comparación de ángulos con quality gate. Ver
`../comparison/README.md` para los límites, fórmula y siguiente incremento.
