# RV Sync v58 — auditoría, causa raíz y plan de recuperación

Fecha de inicio: 2026-08-13 (America/Hermosillo)

## Fase 0 — trazabilidad verificada antes de modificar código

### Repositorios

- APP: rama `fix/rv-main-reconciliation-and-map-sync`, HEAD
  `1fc8ca477b7cf9793a0480169300750caf878f0f`.
- API: rama `fix/rv-main-reconciliation-and-map-sync`, HEAD
  `3986d4b43b0b22fcd8889ac670516171c369ba8c`.
- Ambos árboles estaban limpios después de `git fetch --all --prune`, `git
  switch` y `git pull --ff-only`.
- La API sigue correctamente `origin/fix/rv-main-reconciliation-and-map-sync`.
- La rama APP estaba configurada para seguir `origin/main`, aunque existe y fue
  descargada la ref remota homónima. La comparación confirmó que HEAD local y
  `origin/fix/rv-main-reconciliation-and-map-sync` son el mismo commit. No se
  cambió a `main` ni se hizo reset.

### v53, v57 y pubspec

- `pubspec.yaml` en `0dad2b1` y en HEAD declara `0.2.35+48`.
- APK v53: paquete `com.aquafim.ddr001diag`, versionName
  `0.2.35-recovery-diagnostic`, versionCode `53`, SHA-256
  `CF6E1551475EDCFC940C843CE3458604A07711CE1461772FE9FA3A97430008AC`.
- APK v57: paquete `com.aquafim.ddr001diag`, versionName `0.2.35`, versionCode
  `57`, SHA-256
  `3B4434564FFDCF3312ED4AC8AE3269CF5490A3B82F1236BCF421FE5C31EBCBF4`.
- Las versiones 53–57 se inyectaron mediante opciones de build y no quedaron
  reflejadas en `pubspec.yaml`.
- No existe un commit exclusivo para v53 ni para v57. Fueron construidas desde
  estados intermedios no versionados posteriores a `0dad2b1`; el commit
  consolidado `1fc8ca4` contiene el resultado acumulado (diagnóstico, manejo de
  errores y reconciliación inicial), pero Git no conserva el snapshot exacto de
  cada build intermedia. Los APK y reportes son la evidencia inmutable restante.
- Para v58 se actualizará primero `pubspec.yaml`; no se sobrescribirá el número
  desde la línea de comandos.

### Pixel de prueba

- Serial: `27301FDH3004R7`, estado `device`, modelo Pixel 7 Pro.
- Instalado: `com.aquafim.ddr001diag` `0.2.35+57`.
- `firstInstallTime=2026-08-08 00:17:40`; se preservará mediante
  `adb install -r`.

## Evidencia inicial y problema a demostrar

El reporte productivo v53 contiene 343 registros de fotografías y 343 trabajos
`media_work_queue_v1=pendingUpload`, mientras `media_sync_queue` confirma 226
como `verified`. Esta divergencia se tratará como causa de primer nivel. No se
considerará que una cola de ejecución sea estado de negocio autoritativo.

## Plan de investigación

1. Inventariar writers/readers y transiciones de `visual_inspections_v1`,
   `inspection_photos_v1`, `media_sync_queue`, `media_work_queue_v1`,
   `sync_queue` y `active_inspection_index_v1`.
2. Trazar `RvDraft`, `RvPhotoReference`, `InspectionPhoto`, `MediaSyncStatus` y
   `SyncQueueItem` hasta la UI y los reintentos.
3. Reproducir la divergencia verified/pending con fixtures derivados del reporte
   v53, sin modificar el teléfono productivo.
4. Inspeccionar contratos API de inspección, fotografía, hashes,
   `clientInspectionId`, idempotencia, status agregado y `Retry-After`.
5. Confirmar causas por tests y trazas; no atribuir el incidente al rate limit
   sin status 429, requestId y secuencia temporal.

## Diseño objetivo provisional (sujeto a evidencia)

- Estado remoto `submitted/validated` y fotografía remota `verified` serán
  confirmaciones autoritativas.
- Para un `serverInspectionId`, consultar remoto antes de cualquier escritura;
  reconciliar identidad por inspection, slot y hash/serverPhotoId según el
  contrato real; subir únicamente faltantes; volver a consultar tras upload y
  submit.
- Reparación de primer arranque idempotente, reanudable y no destructiva. Nunca
  eliminar archivos, drafts, respuestas, GPS, señal, válvulas ni cajas Hive.
- Una cola legacy no podrá resucitar trabajo confirmado. Si se confirma que
  `media_work_queue_v1` es legacy, se migrará explícitamente y quedará fuera de
  la decisión de negocio.
- Backoff exponencial con jitter y `Retry-After`; errores deterministas no se
  reintentan automáticamente; una corrida unificada se pausa ante fallo
  sistémico repetido.
- Resultado de sincronización distinguirá ciclo completo, parcial, pausado y
  error determinista.
- Observabilidad persistente y sanitizada integrada en la app normal.

## Riesgos y rollback

- Riesgo principal: asociar una foto remota a una referencia local incorrecta.
  Se exigirá identidad robusta y, ante ambigüedad, se conservará pendiente.
- Riesgo de estados históricos/superseded: no se enviarán si la inspección
  oficial es distinta; se conservará toda la evidencia.
- La migración tendrá versión y será idempotente. El rollback consiste en
  reinstalar por `adb install -r` la build funcional anterior; como no se borran
  archivos ni drafts, la evidencia permanece recuperable.
- No se hará deploy, push, merge ni escritura SQL productiva durante esta labor.

## Validación requerida

- Tests de los casos A–L solicitados, más suite completa APP/API.
- Build desde `pubspec.yaml` con versionCode 58.
- Instalación `adb install -r`, conteos antes/después, reinicio, dos corridas de
  sincronización y verificación de escrituras/duplicados/reintentos.
- El incidente no se declarará resuelto solo por tests o por un caso controlado.

## Resultado de investigación de fuentes de verdad

| Fuente | Escritor principal | Lector/decisión | Hallazgo |
|---|---|---|---|
| `visual_inspections_v1` | `VisualInspectionRepository` / `RvDraftRepository` | Home, detalle, coordinador | Contiene el `RvDraft` y es la fuente documental de la revisión. |
| `active_inspection_index_v1` | repositorio y recovery | apertura de trabajo activo | Índice derivado; puede contener referencias históricas y no debe probar estado remoto. |
| `inspection_photos_v1` | `ReliablePhotoService` / coordinador | validación, galería, upload | Documento duradero de la foto y sus hashes/estado. |
| `media_sync_queue` | coordinador | contadores y pantalla global | Era la fuente efectiva de UI; `verified` proviene de confirmación remota. |
| `media_work_queue_v1` | captura, recovery y reconciliación | recuperación legacy | Cola de ejecución legacy. Se creaba `pendingUpload`, pero nunca se cerraba al verificar. |
| `sync_queue` | `AppState` / repositorio | operaciones no-media | Cola separada; no debe gobernar estado fotográfico. |

### Causa raíz confirmada

Había múltiples estados competidores sin transición atómica:

1. La captura escribía toda foto como `media_work_queue_v1=pendingUpload`.
2. La confirmación remota actualizaba `inspection_photos_v1` y
   `media_sync_queue=verified`, pero no cerraba `media_work_queue_v1`.
3. El reconciliador de arranque recreaba trabajos pendientes para fotos sin
   entrada legacy, incluso si ya estaban verificadas.
4. Una rama del reconciliador degradaba explícitamente una confirmación
   `media_sync_queue=verified` a `uploadedUnverified` cuando el documento estaba
   atrasado.

Esto explica de forma exacta `media_sync_queue verified=226` frente a
`media_work_queue_v1 pendingUpload=343`. La cola legacy no representaba 343
uploads reales; conservaba trabajos de captura nunca cerrados.

### Causas secundarias confirmadas

- El pipeline subía fotos antes de consultar fotos remotas. Una respuesta de
  upload perdida podía causar un reenvío.
- La reconciliación comparaba `local photoId == remote photoId` exclusivamente;
  ignoraba `serverPhotoId`, `client_sha256`, hash normalizado y ambigüedad.
- El backoff quedaba limitado a 45 segundos aun después de cientos de intentos.
- HTTP 429 se clasificaba como servidor no disponible y descartaba
  `Retry-After`.
- El progreso al 100% describía fin del `foreach`, no convergencia real.
- El fallback HTTP podía volver a `Error desconocido` y el diagnóstico técnico
  no se persistía.

La hipótesis CGNAT/rate-limit **no quedó confirmada como causa del reporte v53**:
ese reporte no retuvo status ni headers. Se conserva como riesgo posible; v58
captura la evidencia necesaria si vuelve a ocurrir.

## Nuevo modelo y migración implementados

- `REMOTE VERIFIED` es autoritativo y nunca se degrada por una cola local.
- La cola legacy se conserva, pero se actualiza a un documento `verified`; no se
  elimina evidencia.
- En cada arranque, la reparación idempotente converge documento fotográfico,
  cola de UI, cola legacy y referencias del draft que tengan confirmación
  persistida. No infiere éxito por existencia de archivo.
- Para draft con `serverInspectionId`: GET inspección y GET fotos ocurren antes
  de uploads. Se reconcilia por `serverPhotoId`, ID enviado o hash inequívoco
  dentro del slot. Un match ambiguo permanece pendiente.
- Tras upload se vuelve a consultar fotos; tras submit se hace GET final.
- Create y upload conservan los contratos idempotentes existentes del API.
- Backoff exponencial con jitter, máximo de una hora, y precedencia de
  `Retry-After`. 429 tiene tipo explícito. Dos fallos sistémicos consecutivos —o
  un 429— pausan la corrida sin vaciar la cola.
- Los errores se guardan en `rv_sync_diagnostics_v1` con contexto sanitizado,
  versión/build/SHA/fecha, sin token, coordenadas, respuestas ni binarios.

## API

No fue necesario modificar contratos ni agregar endpoint:

- `POST /inspections` recupera por `(client_inspection_id,user_id)` dentro de
  transacción serializable.
- `POST /inspections/:id/photos` devuelve el registro existente si coinciden
  `photoId`, inspection, slot y client hash.
- `GET /inspections/:id/photos` devuelve `photo_id`, slot, client hash, server
  hash y status.
- `skipSuccessfulRequests: true` permanece intacto. Los headers estándar del
  limitador incluyen `Retry-After`, ahora consumido por Flutter.

