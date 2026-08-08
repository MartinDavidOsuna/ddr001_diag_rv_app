# Firma Android de producción

La aplicación usa `android/key.properties` y el almacén indicado por
`storeFile`. Ambos archivos están excluidos de Git y deben conservarse en un
respaldo seguro, cifrado y con acceso restringido.

La primera APK firmada con esta llave no puede actualizar una instalación
firmada con la llave de depuración: Android exige desinstalarla primero. Desde
esa nueva instalación, las APK posteriores sí se instalan como actualización si
mantienen simultáneamente:

- el mismo `applicationId` (`com.aquafim.ddr001diag`);
- exactamente el mismo keystore y alias;
- un `versionCode` mayor;
- una variante compatible con el dispositivo.

## Compilar producción

```powershell
flutter build apk --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=http://cifra.aquafim.com:3002/api/v1 --dart-define=ALLOW_PRODUCTION_BUILD=true
```

Perder el keystore o su contraseña impide publicar actualizaciones compatibles
con las instalaciones firmadas por esa llave. No se debe regenerar la llave en
cada compilación.
