# Android: APK para repartir

SyncDance se distribuye como APK de Android (7.0 o superior). iOS queda fuera
del alcance por ahora.

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

Con ese archivo, la build de release usa la clave propia:

```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=http://<IP-del-servidor>:8000/api
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk` (unos 93 MB:
incluye el modelo de pose para todas las arquitecturas). Con
`--split-per-abi` se genera un APK por arquitectura, mucho más liviano; la
mayoría de los teléfonos actuales usa `app-arm64-v8a-release.apk`. Hacer copia
de seguridad del `.jks` y sus contraseñas: si se pierden, las instalaciones
existentes no podrán actualizarse.

## Identidad

- `applicationId`: `ai.syncdance.syncdance_mobile`. Cambiarlo crea otra app.
- Nombre visible: **SyncDance** (`android:label` en el manifiesto).
- Versión: `version:` de `pubspec.yaml` (`nombre+código`); subir el código en
  cada APK que se reparta.
