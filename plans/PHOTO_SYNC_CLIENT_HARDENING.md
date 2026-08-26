# PHOTO SYNC CLIENT HARDENING

## 1. Baseline

- Repositorio móvil: `MartinDavidOsuna/ddr001_diag_rv_app`.
- Rama base efectiva: `fix/rv-main-reconciliation-and-map-sync`.
- SHA inicial: `1cf7298daa3a135ad3e579f687a09a98990e3684`.
- Rama de trabajo: `feature/photo-sync-integrity-hardening`.
- API de referencia: `MartinDavidOsuna/ddr001_api`, rama
  `feature/photo-sync-integrity-hardening`, SHA
  `54c76daa84d78c2f370de366a5f058cd0794bdf7`.
- Flutter 3.44.8 / Dart 3.12.2.

## 2. Identidad y actualización Android

- `applicationId`: `com.aquafim.ddr001diag` (sin cambios).
- Anterior: `1.0.0+100`.
- Nueva: `1.0.1+101`.
- Se conserva `android/key.properties` y el `signingConfig` release existente.
- No se renombran cajas Hive, claves de Secure Storage ni preferencias.
- La validación se realiza con `adb install -r`; nunca con uninstall o `pm clear`.

## 3. Persistencia y migración local

La aplicación usa Hive CE con documentos JSON, SharedPreferences y Flutter
Secure Storage. `InspectionPhoto` evoluciona de schema 1 a schema 2 de forma
aditiva. Se conservan todos los campos del schema anterior y se agregan:

- `integrityStatus`;
- `mappingStatus`;
- presencia de original/thumbnail reportada por servidor;
- flags `retryable` y `repairable`;
- intentos y fechas de comprobación/reintento.

El enum legacy `syncStatus` no recibe valores nuevos. Una foto legacy
`verified` conserva ese valor para que 1.0.0+100 pueda leerla, pero la app nueva
la interpreta como `serverConfirmationPending` mientras no exista
`integrityStatus=confirmed`. La migración es silenciosa, idempotente y no toca
archivos, hashes, rutas, revisiones, sesión ni installationId.

## 4. Estados

Los estados fuertes locales son:

- `serverConfirmationPending`;
- `verifying`;
- `confirmed`;
- `missingOriginal`;
- `missingThumbnail`;
- `hashMismatch`;
- `missingMapping`;
- `mappingConflict`;
- `deleted`;
- `notVerified`;
- `notFound`;
- `capabilityUnavailable`;
- `retryRequired`.

Sólo `confirmed` cuenta como evidencia sincronizada. El estado funcional de la
revisión (`submitted`, `validated`, etc.) permanece independiente.

## 5. Contrato API

Se consume `POST /api/v1/photos/verify-batch` con autenticación field y lotes de
máximo 100 UUID. Se interpretan exactamente `confirmed`, `missing_original`,
`missing_thumbnail`, `hash_mismatch`, `missing_mapping`, `mapping_conflict`,
`deleted`, `not_verified` y `not_found`, junto con `originalPresent`,
`thumbnailPresent`, `storageVerified`, `mapped`, `mappingStatus`, `retryable`,
`repairable` y `serverSha256`.

No se consume ningún endpoint admin ni se envían report/version targets. La API
autorrepara thumbnail o mapping únicamente cuando puede demostrar una relación
inequívoca y devuelve el estado posterior a esa reparación.

## 6. Flujo y reconciliación

El flujo nuevo es `captura -> cola -> upload -> uploadedUnverified ->
verify-batch -> confirmed`. Un 200/201 nunca confirma por sí mismo.

La reconciliación por revisión reúne referencias obligatorias y adicionales,
documentos locales, archivos, hashes, slots y estado de cola; consulta la API en
lotes y aplica cada resultado aisladamente. Las revisiones finalizadas con
evidencia legacy también entran a reconciliación sin volver a draft.

Política:

- `confirmed`: confirma y conserva el archivo local.
- `missing_original`: re-upload con mismo photoId si existe original local.
- `hash_mismatch`: re-upload controlado con mismos bytes/UUID/hash local.
- `not_found`: re-upload con mismo photoId si el archivo local existe.
- `not_verified`: re-upload sólo si API indica retryable y hay archivo.
- `missing_thumbnail`: nunca re-upload; esperar reparación API/verificar.
- `missing_mapping`: nunca re-upload; esperar reparación API/verificar.
- `mapping_conflict`: no mutar ni reintentar automáticamente; requiere revisión.
- `deleted`: no resucitar automáticamente.

## 7. Cola, retries y fallback

Se reutilizan `media_sync_queue`, `media_work_queue_v1` y `sync_queue`. Los
trabajos persistidos distinguen upload, verify, revisión y retry. Los reintentos
usan backoff exponencial (base 5 s, tope 1 h) con jitter y fecha persistida.

Si verify-batch responde 404/405 se registra `capabilityUnavailable`, se
conserva toda la evidencia y se aplica cooldown de seis horas. No se hace
re-upload masivo y el flujo legacy restante sigue disponible.

## 8. Retención local y UX

El original no se elimina después del upload ni después de confirmarse. La
política es conservadora para permitir recuperación futura. Captura y thumbnail
siguen siendo inmediatos; upload y verificación ocurren fuera de la interacción
de captura.

La pantalla existente usa: Sincronizado, Sincronizando, Información pendiente,
Sin conexión y Requiere reintento/revisión. No muestra hashes, UUID, paths,
HTTP, requestId ni mapping técnico.

## 9. Logging

Los diagnósticos registran categorías de migración, upload, verificación,
re-upload, conflicto y retry. No se registran tokens, secretos, bytes de imagen
ni respuestas de autenticación.

## 10. Pruebas

Las pruebas cubren lectura schema 1, migración aditiva/idempotente, conservación
de ruta/hash/archivo, adopción legacy, parsing de verify-batch, límite de 100,
confirmación y política de re-upload/no-re-upload. La suite completa y
`flutter analyze` forman parte del gate de entrega.

## 11. Rollback

Los documentos schema 2 conservan `syncStatus` con valores conocidos por
1.0.0+100; los campos nuevos son ignorados por su parser JSON. Por ello la
lectura local es compatible hacia atrás. Android no permite instalar normalmente
un versionCode menor con `adb install -r`; un rollback binario requiere el
procedimiento de distribución/firma autorizado y debe probarse antes. Volver a
1.0.0+100 también pierde la semántica de confirmación fuerte y no se recomienda
como operación de campo.

## 12. Troubleshooting

- 404/405 de verify-batch: rollout API incompleto; esperar cooldown, sin borrar.
- `mappingConflict`: revisar en plataforma/API; la app no adivina mappings.
- original remoto faltante sin copia local: conservar incidencia; no fabricar.
- rechazo de `adb install -r`: comparar certificado y versionCode; no desinstalar.
- cola persistente: inspeccionar estado sanitizado en diagnóstico, sin tokens.

## 13. Certificación Android

La certificación exige un dispositivo real con 1.0.0+100, sesión activa,
revisiones, fotos y pendientes. Se registra installationId y conteos antes; se
cierra la app, se instala 1.0.1+101 con `adb install -r` y se comparan los mismos
datos después. Sin dispositivo, el resultado debe reportarse como
`IMPLEMENTADO — PENDIENTE CERTIFICACIÓN ANDROID`.
