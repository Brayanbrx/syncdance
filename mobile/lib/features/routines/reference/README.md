# Fase 3 · Paso 2 — referencias móviles

Implementado el 2026-10-01. Validación física e integración con un servidor real
pendientes; no se declara cerrado el entrenamiento offline completo.

## Flujo disponible

1. Ingresar con una cuenta existente de Django. `auth/login/` obtiene el JWT y
   `auth/me/` confirma la identidad antes de abrir Inicio.
2. Abrir **Rutinas** para consultar el catálogo paginado y descargar la última
   referencia READY de una rutina accesible.
3. Consultar duración, muestras y cobertura en **Referencias guardadas**, incluso
   sin red durante la sesión. Se pueden eliminar versiones individualmente.
4. **Inicio → Cambiar cuenta** cierra la sesión. **Continuar sin cuenta** permite
   usar la cámara y la detección local sin solicitar datos protegidos.

La contraseña y el access token nunca se guardan en disco. Desde Fase 6, paso 2,
`CatalogSession` guarda en almacenamiento seguro (Keychain/Keystore) solo la
identidad y el refresh token, por servidor. Al reiniciar, la app abre Inicio sin
red con la cuenta anterior y renueva el access token en el primer uso. Un 401
renueva una vez y reintenta; llamadas simultáneas comparten una sola renovación,
porque el servidor rota y revoca cada refresh usado (30 días de vida). Si el
refresh es rechazado se conserva la identidad para datos locales y la red pide
ingresar de nuevo. **Cambiar cuenta** borra la entrada y revoca el refresh.
Android desactiva el backup automático para no restaurar claves inválidas.
No hay registro móvil. HTTP local está permitido en Android debug; para release
se requiere HTTPS.

## Contrato y almacenamiento

- `CatalogApi`: login, catálogo, metadatos y gzip con JWT. Solo acepta URLs del
  mismo origen y bajo la ruta API configurada; no sigue redirecciones.
- `decodeReference`: verifica SHA-256 de los bytes originales, estado READY,
  esquemas/versiones compatibles, procedencia, duración, muestras a 12 Hz,
  ángulos finitos de 0–180°, joints conocidos y cobertura consistente.
- Las muestras sin ángulos conservan su lugar en el timeline. Un torso parcial
  normalizado puede tener calidad NO_USABLE_POSE sin invalidar todo el archivo.
  La ausencia de una medida nunca se convierte en cero.
- `ReferenceCache`: almacenamiento privado dividido por servidor/cuenta, archivo
  independiente por rutina/versión/checksum, escritura temporal y rename final.
  Verificación y parseo fuera del isolate de UI. Al reabrir, se revalidan los
  archivos; entradas corruptas o temporales no se ofrecen en la lista.
- Límites: 8 MiB por descarga, 16 MiB al descomprimir, 12 MiB por envelope y
  64 MiB en disco por cuenta/servidor. Si no hay espacio se rechaza la nueva
  versión, conservando las anteriores; no hay desalojo automático.

La cobertura expresa muestras con algún ángulo utilizable; no es una puntuación
ni una certificación de calidad de la rutina. Desde Fase 4, paso 4, el lector
entrega ángulos y coordenadas normalizadas inmutables para comparar ambos en el
móvil. Conserva el mismo formato cacheado; no requiere regenerar las referencias.
Una muestra con algún ángulo puede seguir siendo insuficiente para el matcher,
que exige seis ángulos y doce posiciones completas.

## Validación

Resultado al cerrar el paso: 89 pruebas Flutter y 33 pruebas backend aprobadas;
2 pruebas nativas opcionales omitidas. Formato y análisis estático sin incidencias,
checks de Django/migraciones/esquema correctos y APK Android debug compilado.
El APK no se instaló en el teléfono.

Las pruebas de API simulan login, permisos, paginación, URLs, redirecciones y
límites de descarga. Las de caché usan archivos reales y verifican reapertura,
separación por cuenta/servidor, corrupción, actualizaciones fallidas y cuota.
Las de widgets recorren login válido/fallido, descarga, consulta sin red y borrado.
Python verifica que la fixture gzip compartida corresponde exactamente a su
generador; Dart la decodifica, incluidas las muestras sin ángulos.

Prueba manual pendiente: configurar API_BASE_URL y DJANGO_ALLOWED_HOSTS, publicar
una rutina y esperar READY, ingresar desde Android, descargar y consultar sus
datos; desconectar la red y volver a abrir Rutinas dentro de la sesión. Después,
reconectar, reiniciar e ingresar con la misma cuenta para comprobar persistencia,
cambiar de cuenta para verificar separación y eliminar una versión.

La continuación de este paso ya incorpora video maestro reproducible y consulta
del timeline por posición del reproductor. Ver `../../training/playback/README.md`.
La comparación y puntuación (Fase 4) ya están implementadas; ver
`../../training/comparison/README.md`.
