# Enrutamiento QA y compatibilidad con API clean

## Baselines y alcance

- RV baseline: `origin/main` en `792070d192318cffaef8f0ddfbd13bb6d914317e`
  (`v1.0.16+116`).
- Rama QA: `qa/rv-clean-api-e2e`, creada directamente desde ese baseline.
- Commit funcional QA validado:
  `2f40996f49376612afdd019a12ea3ec29fb520dd`.
- API local: `release/api-idempotency-hardening-clean` en
  `ecf7438d59133f8a06a4cdb3c34f3ac594c73223`.
- Base: `DDR001_Hidrantes_TEST`.
- Storage: storage local TEST dedicado.
- Dispositivo: Motorola moto g14, Android 14 / API 34.
- Package QA: `com.aquafim.ddr001diag.qa`, versión `1.0.16-qa+116`.
- Producción tocada durante esta corrida: **NO**.
- API desplegada o mergeada: **NO**.
- RV desplegada o mergeada: **NO**.
- API TEST iniciada para el gate y detenida limpiamente: **SÍ**.

Esta validación no modifica lógica funcional de revisión, cámara, checklist,
sincronización, fotos o mapa. Sólo agrega infraestructura de configuración y
seguridad para ejecutar QA contra una API local.

## Causa del incidente previo

El flavor productivo usado en el smoke anterior tenía la URL productiva
compilada. La prueba confió en el proxy global de Android, pero Dio abrió la
conexión usando la URL configurada en el cliente. La aplicación no validaba la
relación entre ambiente, package y host antes de construir `ApiClient`.

El incidente y sus límites están documentados en
`docs/RV_ACCIDENTAL_PRODUCTION_TOUCH.md`. La build implicada fue detenida antes
de esta corrida.

## Mecanismo QA seguro

La ejecución QA usa parámetros compilados explícitos:

```text
--flavor qa -t lib/main.dart
--dart-define=APP_ENV=qa
--dart-define=API_BASE_URL=http://127.0.0.1:3003/api/v1
```

Android encaminó loopback mediante `adb reverse tcp:3003 tcp:3003`. Antes de
crear el cliente HTTP, bootstrap valida que:

- `APP_ENV=qa` sólo pueda ejecutarse en el package QA;
- el package QA no pueda arrancar con otro ambiente;
- QA sólo acepte `127.0.0.1` o `localhost`, con ruta exacta `/api/v1`;
- QA rechace producción, URL vacía y hosts desconocidos;
- producción rechace loopback.

El manifest QA mantiene cleartext desactivado globalmente. Su Network Security
Config concede cleartext únicamente a loopback. El `applicationIdSuffix=.qa`
aísla package, datos, SharedPreferences, Hive, Secure Storage, tokens e
installation ID respecto de producción.

La ejecución registró sólo valores sanitizados:
`APP_ENV=qa API_HOST=127.0.0.1`. No se imprimieron credenciales ni tokens.

## Matriz de seguridad S1-S6

| Caso | Resultado | Evidencia |
|---|---|---|
| S1 production + URL productiva | PASS | Configuración productiva existente aceptada. |
| S2 QA + URL TEST loopback | PASS | Package QA inició y el primer request llegó a API TEST. |
| S3 QA + URL productiva | PASS | Bootstrap rechazó la configuración antes del primer request. |
| S4 QA + URL vacía | PASS | Configuración rechazada. |
| S5 QA + host desconocido | PASS | Configuración rechazada. |
| S6 production + URL local | PASS | Configuración rechazada. |

Prueba negativa Android: una build QA compilada con el host productivo mostró
error fatal de configuración y generó cero requests. Resultado:
`QA PROD NETWORK GUARD: PASS`.

## Smoke E2E físico RV01-RV14

| Caso | Resultado | Evidencia |
|---|---|---|
| RV01 Startup | PASS | Bootstrap y primera pantalla sin crash ni pantalla negra. |
| RV02 Login/session | PASS | Sesión TEST restaurada tras force-stop y conservada durante caída temporal. |
| RV03 Hydrants | PASS | Catálogo TEST 1176/1176, listado y búsqueda visibles. |
| RV04 Map | PASS | Mapa cargó hidrantes, selección y navegación a detalle. |
| RV05 Existing inspection | PASS | Revisión TEST existente abrió checklist, estado, fotos y metadata. |
| RV06 New inspection | PASS | Borrador local con UUID estable y una revisión única creada en TEST. |
| RV07 Real photo | PASS | Una fotografía real del dispositivo fue incorporada mediante el selector RV; siete evidencias quedaron durables con metadata. La toma directa con botón de cámara no fue necesaria para este gate. |
| RV08 Photo integrity | PASS | Cliente mostró `7 verificadas`; servidor TEST confirmó 7/7, IDs únicos. |
| RV09 Idempotent retry | PASS | Se descartó una respuesta 2xx de una mutación con Idempotency-Key; el retry usó la misma key y no duplicó efectos. |
| RV10 Force-stop | PASS | Sesión, revisión, archivos y operación pendiente sobrevivieron y continuaron. |
| RV11 Reconciliation | PASS | Tras restaurar API/conectividad, la cola terminó en `Todo sincronizado`. |
| RV12 Multiple inspections | PASS | Una segunda revisión local del mismo hidrante obtuvo UUID independiente sin sobrescribir la anterior. |
| RV13 API temporary failure | PASS | API TEST detenida: sesión, revisión, fotos y cola permanecieron; al reiniciar recuperó sync. |
| RV14 Final reopen | PASS | Force-stop final conservó sesión, revisión, fotos y estados. |

La nueva revisión usada para evidencia permaneció `in_progress` porque el submit
final fue interrumpido antes de completarse. No se atribuye un submit que no se
ejecutó; creación, carga, verificación, retry y persistencia sí quedaron
demostrados.

## Integridad, idempotencia y duplicados

Verificación read-only en TEST para la revisión del gate:

- fotos activas: 7;
- fotos `integrity_status=confirmed`: 7;
- `photoId` únicos: 7;
- slots duplicados: 0;
- resultados idempotentes comprometidos para la mutación observada: 1.

La respuesta exitosa descartada correspondió a una operación RV real. El
cliente reintentó con la misma Idempotency-Key; la API hizo replay seguro y el
resultado lógico quedó único.

## Regresión y estabilidad

- `flutter analyze`: PASS, 0 issues.
- `flutter test`: PASS, 593/593.
- `integration_test/offline_startup_test.dart` en Motorola/package QA: PASS,
  1/1.
- crashes: 0.
- ANR: 0.
- OOM: 0.
- duplicados: 0.
- regresiones funcionales RV nuevas: 0.

`logcat` no mostró `FATAL EXCEPTION`, ANR u `OutOfMemoryError`. El historial de
salida Android sólo registró cierres solicitados/force-stop usados por el gate.

## Resultado

La app RV real, aislada en package QA y con barrera interna de host, es
compatible con la API clean local certificada. La producción no fue contactada
durante esta corrida. Ningún componente fue desplegado o mergeado.

`RV_CLEAN_API_E2E_COMPATIBLE`
