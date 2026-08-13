# Validación Pixel 7 Pro — v57

- Fecha local: 2026-08-12 (America/Hermosillo)
- Dispositivo: Pixel 7 Pro `27301FDH3004R7`
- Paquete: `com.aquafim.ddr001diag`
- Instalación: actualización en sitio mediante `adb install -r`
- Datos preservados: `firstInstallTime=2026-08-08 00:17:40`
- Versión instalada: `versionName=0.2.35`, `versionCode=57`

## Resultado

La aplicación inició correctamente con Wi-Fi. No hubo excepción fatal ni error
HTTP nuevo en el arranque observado. La proyección y el estado local quedaron
consistentes para la cuenta 1497:

- Inicio: `0 Pendientes de sincronizar`
- Inicio: `2 Enviados`
- Revisión reciente: `Cuenta 1497 — Terminada`

La v55 había demostrado que la conexión y la API estaban disponibles y avanzó
el mismo draft hasta `submit`, pero dejó el `syncError` anterior. La v57 corrige
esa condición al consultar primero una inspección remota ya identificada y
reconciliar `submitted` localmente, incluso cuando la respuesta original de
submit se perdió. Los drafts oficiales diferentes continúan tratándose como
superseded y no se reenvían.

## Validación automática

- `flutter analyze`: sin hallazgos.
- `flutter test`: 345 pruebas aprobadas.
- APK: `dist/rv-diagnostics/ddr001-rv-functional-fix-v57.apk`.

## Hallazgo sistémico pendiente de despliegue

El API aplica un límite global de 100 solicitudes/minuto por IP. Una revisión
visual realiza numerosas solicitudes y varios teléfonos bajo CGNAT móvil pueden
compartir la misma IP. Esto permite que Internet y el servidor estén en línea,
pero que solicitudes válidas reciban 429. El cliente anterior convertía esa
respuesta en un mensaje genérico de comunicación y no conservaba el detalle.

Se preparó una corrección del API para no consumir el presupuesto del limitador
con solicitudes exitosas. No fue desplegada ni se modificaron datos de
producción durante esta validación.
