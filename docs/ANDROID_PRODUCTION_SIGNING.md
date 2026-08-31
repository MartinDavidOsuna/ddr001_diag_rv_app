# Firma Android de producción de RV

El package productivo es `com.aquafim.ddr001diag`. Todas las APK productivas
históricas conocidas usan este certificado público SHA-256:

`d1d9ec17be22dff0320afed5c2e3031e013738beaee35c7303fd8ac18485af2c`

La clave privada, sus contraseñas y `android/key.properties` nunca deben
versionarse. El fingerprint público sí se conserva en
`tool/production_signing.env` para prevenir releases incompatibles.

## Regla invariable

Nunca regenerar, reemplazar ni rotar el keystore para resolver un fallo de
actualización. Android sólo permite actualizar una instalación cuando package y
certificado son compatibles. Cambiar el certificado obliga a desinstalar y
provoca pérdida de los datos privados de la aplicación.

El keystore histórico debe recuperarse únicamente desde la ubicación
corporativa autorizada. `android/key.properties` debe apuntar localmente a ese
archivo y permanecer ignorado por Git. Este documento no contiene alias ni
contraseñas.

## Build productivo

```bash
tool/build_apk_with_metadata.sh \
  --release \
  --flavor production \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=http://cifra.aquafim.com:3002/api/v1 \
  --dart-define=ALLOW_PRODUCTION_BUILD=true
```

Al finalizar, el script valida automáticamente certificado, package y que el
manifest no sea debuggable. También puede validarse un artefacto existente:

```bash
tool/verify_production_signing.sh path/to/app-production-release.apk
```

## Prueba de actualización

Primero verificar la APK. Después registrar la versión instalada y ejecutar:

```bash
adb shell dumpsys package com.aquafim.ddr001diag | grep version
adb install -r path/to/app-production-release.apk
```

El resultado debe ser `Success`. No desinstalar, borrar datos ni usar `pm clear`
durante una actualización ordinaria. Si aparece
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, detenerse y comparar certificados; nunca
crear otra llave como solución.
