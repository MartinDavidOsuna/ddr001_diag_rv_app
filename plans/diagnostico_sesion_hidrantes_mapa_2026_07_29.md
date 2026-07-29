# Diagnóstico de sesión, hidrantes y mapa — 2026-07-29

## Alcance

- Aplicación Flutter `ddr001_diag_rv_app`.
- API `ddr001_api_rv`.
- Pruebas remotas exclusivamente de lectura contra la URL autorizada.
- Sin despliegue, commit, push ni mutaciones en producción.

## Estado inicial

- Flutter: rama `fix/startup-login-sync-performance`, HEAD `eaa25fb`.
- API: rama `diagnostico-produccion-2026-07-28`, HEAD `70e3419`.
- Flutter conserva cambios locales previos que no deben revertirse.
- Versión inicial: `0.2.3+16`.
- `applicationId` y `namespace`: `com.aquafim.ddr001diag`.

## Diagnóstico preliminar

1. `ApiClient._onError` intenta renovar un `401`, pero borra el almacenamiento
   seguro ante cualquier excepción del refresh, incluidas fallas temporales de
   red.
2. `_performRefresh` también borra la sesión ante cualquier excepción.
3. La excepción original se vuelve a propagar y `ApiException` la muestra como
   `Tu sesión expiró`, aunque la renovación haya fallado por transporte.
4. Catálogo y mapa usan el mismo cliente autenticado, por lo que pueden compartir
   la falla de renovación.
5. La configuración Android ya limita cleartext a `cifra.aquafim.com`; no se
   habilitará HTTP global en release.

## Etapas

1. Confirmar contratos y estados de revocación de la API.
2. Ejecutar smoke tests GET protegidos y sin credenciales.
3. Corregir la clasificación de refresh temporal versus revocación definitiva.
4. Conservar sesión, borradores, fotografías y cola ante errores recuperables.
5. Exponer estado `requiresAuthentication` en la cola persistente.
6. Mejorar errores de catálogo y mapa sin vaciar caché.
7. Agregar pruebas unitarias, de widgets, integración local y smoke explícito.
8. Documentar arquitectura, compilación y validación.
9. Incrementar PATCH y build una vez, validar y generar APK con versión.

## Riesgos

- Las lecturas autenticadas no pueden ejecutarse sin una credencial de prueba
  segura.
- La URL autorizada usa HTTP; la solución definitiva requiere HTTPS.
- Las pruebas físicas requieren un dispositivo Android disponible.

## Criterios de aceptación

- Un refresh temporalmente fallido no borra credenciales ni datos locales.
- Solo una revocación confirmada exige autenticación nuevamente.
- Una solicitud se reintenta como máximo una vez después del refresh.
- Solicitudes concurrentes comparten una única renovación.
- Catálogo y mapa conservan y muestran caché ante fallos parciales.
- Los smoke tests remotos son opt-in y solo ejecutan GET.
- Flutter y API superan sus validaciones.
- APK generada con versión incluida en el nombre.

## Resultado

- Causa de sesión: el cliente borraba Secure Storage ante cualquier fallo del
  refresh y el refresh de campo tenía una vigencia predeterminada de 24 horas.
- Causa de catálogo: las rutas están desplegadas, pero requieren autenticación;
  una renovación temporalmente fallida eliminaba el token y dejaba catálogo
  principal, asignaciones y estadísticas en error parcial.
- Causa de mapa: `/hydrants/map` está desplegado; comparte el cliente y la misma
  falla de renovación. El mensaje genérico ocultaba si era autenticación,
  timeout o transporte.
- Producción/desarrollo respondió `200` para live, ready y version. Listado,
  snapshot y mapa respondieron `401` sin credencial, confirmando ruta y
  protección.
- No se ejecutó ninguna operación remota de escritura.
- La lectura autenticada de hidrantes y mapa queda pendiente de una credencial
  de prueba segura.
- Versión final: `0.2.4+17`.
- `flutter analyze`: sin problemas.
- `flutter test`: 249 pruebas aprobadas, incluida la persistencia completa de
  respuestas y referencias fotográficas tras un `401`.
- API: 102 pruebas unitarias y 12 de integración aprobadas; build correcto.
- APK release: `dist/ddr001_diag_rv_app-0.2.4+17.apk`.
- SHA-256:
  `C59843D15ECFA4B18AEF6146CA68A1B55333156E3BC39C56B05890C2BAB214AF`.
