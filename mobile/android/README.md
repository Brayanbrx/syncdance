# Android: APK para repartir

SyncDance se distribuye como APK de Android (7.0 o superior), desde la landing
del propio servidor y sin Google Play. iOS queda fuera del alcance por ahora.

## Firma de release

Android solo actualiza una app instalada con un APK firmado con **la misma
clave**. Sin clave propia, `flutter build apk --release` firma con la clave de
depuración de ese computador: sirve para probar, pero un APK compilado en otro
equipo no actualizará el instalado (hay que desinstalar y se pierde el
historial local que no se haya sincronizado).

Crear la clave una sola vez y guardarla fuera del repositorio:

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\syncdance-release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias syncdance
```

Crear `mobile/android/key.properties` (ignorado por git):

```properties
storeFile=C:/Users/<usuario>/syncdance-release.jks
storePassword=<contraseña>
keyAlias=syncdance
keyPassword=<contraseña>
```

Hacer copia de seguridad del `.jks` y sus contraseñas fuera del computador: si
se pierden, las instalaciones existentes no podrán actualizarse nunca más.

## Publicar una versión

1. Compilar con el servidor de producción, que **debe ser HTTPS**. Android
   bloquea `http` fuera de las builds de depuración. Una build de release sin
   servidor HTTPS no intenta conectarse: muestra «Esta copia de la app no tiene
   configurado el servidor».

   ```powershell
   cd mobile
   ./scripts/build_release.ps1 -Server https://<dominio> -Version 1.1.0 -Build 2
   ```

   El script se niega si falta `key.properties`, si el servidor no es HTTPS o
   si el código no es mayor que el de la versión publicada. Al terminar
   imprime el tamaño y el SHA-256 de cada APK.
2. Subir `build/app/outputs/flutter-apk/app-release.apk` en
   `https://<dominio>/panel/app`. La versión y el código se leen del propio APK
   (si no coinciden con lo escrito, la subida se rechaza).
3. Publicarla. Desde ese momento la landing la ofrece y **la app avisa a cada
   alumno** con una versión anterior al abrir el inicio: «Hay una versión nueva…
   Descargar». Al instalarla encima se conservan las prácticas y rutinas
   guardadas (misma clave, mismo `applicationId`).

El APK completo pesa unos 94 MB porque incluye el modelo de pose para todas
las arquitecturas. Con `-SplitPerAbi` se genera uno por arquitectura, mucho
más liviano; la mayoría de los teléfonos actuales usa
`app-arm64-v8a-release.apk`. La landing ofrece un solo APK: para repartir los
livianos hay que elegir uno (arm64-v8a cubre casi todos los teléfonos de los
últimos años).

## Servidor en un VPS (Azure, AWS u otro)

La app necesita un nombre con certificado HTTPS. Caddy lo obtiene solo
(`ops/README.md`) si el nombre apunta al VPS y los puertos 80 y 443 están
abiertos en el firewall del proveedor (grupo de seguridad en AWS, NSG en
Azure). Sirve un dominio propio o el nombre que da el proveedor: en Azure,
`<nombre>.<región>.cloudapp.azure.com`. En AWS, Let's Encrypt no emite
certificados para los nombres `*.amazonaws.com`: hace falta un dominio propio.
Una IP sola no sirve.

## Errores en los teléfonos

Las builds de release envían sus fallas a `POST /api/app/errors/`: tipo de
error, primeras líneas de la pila y versiones de la app y del sistema; nunca
la cuenta, imágenes ni poses. Se agrupan por versión y lugar (con un
contador) y se ven en Django Admin, «Errores de la app». En «Mi cuenta» la app
muestra su versión, lo primero que conviene preguntar en soporte.

## Identidad

- `applicationId`: `ai.syncdance.syncdance_mobile`. Cambiarlo crea otra app.
- Nombre visible: **SyncDance** (`android:label` en el manifiesto).
- Ícono: una figura bailando sobre el índigo de la marca, con su lado
  izquierdo naranja y el derecho celeste, como la app colorea los lados del
  cuerpo. Ícono adaptable en `res/drawable/ic_launcher_foreground.xml` y PNG
  para Android 7 en `res/mipmap-*`.
- Versión: `--build-name` (visible) y `--build-number` (`versionCode`, sube en
  cada APK) del script; `pubspec.yaml` queda en `1.0.0+1` para desarrollo.
