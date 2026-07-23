# DDR001 DIAG RV — validación Android

> Versión interna de validación. No es una entrega productiva ni debe publicarse. Usa firma debug.

- Versión: `0.2.1+4` (Android reporta `versionName 0.2.1`, `versionCode 4`).
- Fecha: 2026-07-22.
- Ambiente: `development`.
- API: `http://192.168.1.111:3000/api/v1`.
- Package: `com.aquafim.ddr001diag`.
- APK universal: `DDR001_DIAG_RV_0.2.1_debug.apk`.
- SHA-256: `5283FD6F6AF7FFC9DB6D9ECC3F712C99C52BB84C1B6765C612018D35E7380416`.
- Los APK separados por ABI se generaron para medir tamaño, no son el artefacto oficial del piloto: Flutter añade un prefijo ABI al `versionCode` (por ejemplo, arm64 muestra `2004`).

## Instalación

Habilitar depuración USB, autorizar la computadora y comprobar `adb devices`. Para actualizar conservando datos:

```powershell
adb install -r .\DDR001_DIAG_RV_0.2.1_debug.apk
```

Para una instalación limpia, desinstalar primero `com.aquafim.ddr001diag`; esto elimina los datos locales. El teléfono debe estar en la misma red que `192.168.1.111` y poder acceder al puerto 3000.

## Permisos

La app solicita cámara y ubicación durante el flujo. Probar concedido, denegado, denegado permanentemente y ubicación desactivada. No conceder permisos adicionales por ADB: deben validarse mediante la interfaz real.

## Recorrido mínimo

1. Registrar un inspector ficticio, sin datos personales reales.
2. Descargar hidrantes y checklist; comprobar búsqueda y caché.
3. Crear una inspección, contestar parcialmente y capturar GPS.
4. Capturar los slots `front_closed`, `left_side`, `right_side`, `back`, `top`, `front_open` y `serial_plate`.
5. Activar modo avión, continuar, cerrar desde recientes y volver a abrir.
6. Confirmar restauración; reconectar y pulsar **Sincronizar ahora**.
7. Revisar resumen, enviar y comprobar modo solo lectura.
8. Verificar el registro en API, SQL Server de desarrollo y dashboard.

## Datos y evidencia

Usar nombres/correos/teléfonos ficticios identificables como prueba y fotografías sin personas, placas vehiculares o documentos. Al reportar, incluir dispositivo, Android, versión, pantalla, pasos, resultado, severidad y evidencia saneada en `plans/07_incidencias_piloto_android.md`.

## Problemas conocidos

- La validación interactiva completa de permisos, GPS, cámara, modo avión, siete fotos y submit queda pendiente del operador del dispositivo.
- El plugin `flutter_image_compress_common` emite una advertencia de compatibilidad futura con Built-in Kotlin; no bloquea esta compilación.
- `flutter build apk --debug --analyze-size` no está soportado por Flutter; los tamaños se midieron por archivo y contenido ZIP.
- El APK universal debug es grande porque incluye kernel/snapshots debug y librerías para tres ABI. Se conserva como piloto oficial para mostrar exactamente `0.2.1+4`.

No compartir secretos, llaves de firma, tokens ni datos personales. Para una distribución más amplia debe configurarse firma productiva y Play Internal Testing en una etapa posterior.
