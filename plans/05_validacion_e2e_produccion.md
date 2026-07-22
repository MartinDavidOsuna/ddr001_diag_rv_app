# Validación E2E y preparación de producción

Fecha: 2026-07-22. Rama Flutter: `feature/rv-inspection-flow`.

## Contrato fotográfico final

Flutter normaliza a JPEG, termina de escribir el archivo durable, lee `finalBytes`, valida que pueda decodificarse y calcula SHA-256 sobre esos bytes. `localPath` apunta al mismo archivo y Dio lo abre directamente al construir `MultipartFile`; no existe transformación posterior. El UUID de `InspectionPhoto` se persiste en Hive y se reutiliza en cada retry.

La API valida `clientSha256` contra el buffer multipart recibido y devuelve `normalizedSha256` para el archivo final de Sharp. Flutter acepta el nuevo campo y mantiene fallback a `sha256`/`server_sha256` para compatibilidad. No cambiaron DTO persistente, cola ni UUID.

## E2E automatizado

Ejecutado contra `RevisionVisualStarter_Test`, nunca producción. El test creó un hidrante `RV-E2E-{UUID}`, sesión e inspección, descargó checklist, guardó respuestas/GPS/señal, verificó que submit incompleto devolviera 422, cargó los siete slots con PNG generados, comprobó `clientSha256 != normalizedSha256`, reintentó el mismo UUID sin duplicar, listó siete fotos, descargó miniatura, envió y confirmó `submitted`. Resultado: 2/2 integraciones aprobadas. El fixture limpia inspección/historial/hidrante/archivos.

## Prueba manual Android pendiente

No hubo dispositivo interactivo. No se declara ejecutada. Procedimiento:

```powershell
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
```

Iniciar sesión; seleccionar hidrante; crear RV; contestar; GPS/señal; tomar siete fotos; activar modo avión; cerrar/reabrir; confirmar restauración y continuación offline; reconectar; sincronizar; comprobar siete fotos; submit; verificar API, SQL y dashboard. Registrar cuenta, `clientInspectionId`, `serverInspectionId`, siete UUID, hashes y timestamps sin tokens.

## Validaciones y rollback

Flutter debe ejecutar `flutter pub get`, `dart format .`, `flutter analyze`, `flutter test` y APK debug. El rollback Flutter consiste en retirar solamente la preferencia por `normalizedSha256`; el alias antiguo permite compatibilidad. No hay migración ni secretos nuevos.

Riesgos: prueba física pendiente, endpoint de reemplazo de slot inexistente y advertencia futura del plugin de compresión/Kotlin.

## Preparación piloto Android 0.2.1+4

Fecha: 2026-07-22. Rama: `test/rv-android-pilot`.

La API de desarrollo respondió correctamente en `/health/live` (`status: ok`) y `/health/ready` (`database`, `storage` y `configuration`: `ok`). Se usó un Pixel 7 Pro arm64 con Android 17/API 37, autorizado por ADB y con 32 GB libres. La actualización sobre `0.2.0+3` conservó `firstInstallTime`; después, la instalación limpia de `0.2.1+4` también fue exitosa y la app abrió. El dispositivo alcanzó TCP/3000 de la API. Cámara y ubicación quedaron declaradas y sin conceder después de la instalación limpia, como corresponde antes de solicitarlas desde UI.

La versión se incrementó de `0.2.0+3` a `0.2.1+4` porque el APK se prepara para distribución interna. Se conserva `com.aquafim.ddr001diag` y el nombre `DIAGNOSTICO HIDRANTES`. Se agregaron trazas de sincronización exclusivas de debug con identificador abreviado, etapa, slot e intento; no contienen tokens, correo, teléfono, bytes ni rutas de fotos.

El bloqueo inicial de `flutter` fue causado por el sandbox, que impedía crear `C:\flutter\bin\cache\lockfile`; al ejecutar los comandos estándar con permiso para el SDK, doctor, analyze, tests y builds terminaron correctamente. No se modificó manualmente el SDK. Persisten pendientes la interacción en pantalla para sesión, permisos, GPS real, cámara, modo avión, cierre forzado, siete fotos, submit y verificaciones de SQL/dashboard; no se declaran aprobadas.

`flutter analyze`: sin incidencias. `flutter test`: 116/116 aprobadas. APK universal: 155.53 MiB; arm64: 87.82 MiB; armeabi-v7a: 67.87 MiB; x86_64: 74.47 MiB. `--analyze-size` no admite debug. El desglose ZIP muestra que el peso principal corresponde a `kernel_blob.bin` debug (74.86 MiB crudos) y motores/librerías nativas por ABI, no a los assets declarados de la aplicación.
