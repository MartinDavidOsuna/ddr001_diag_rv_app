# Diagnóstico de convergencia productiva v59

Fecha de corte: 2026-08-14 UTC  
APP: `392d1cad9ae74370667b64fd59d89b7bfe1c6c64`, `0.2.37+59`  
API observada: producción `http://cifra.aquafim.com:3002/api/v1`  

## Alcance y nivel de evidencia

- **CONFIRMADO servidor:** respuestas GET de `/admin/hydrants`, `/admin/inspections` y `/admin/inspections/{id}`.
- **CONFIRMADO código:** comportamiento exacto de APP v59.
- **NO DISPONIBLE:** Hive y `rv_sync_diagnostics_v1` del teléfono productivo. El Pixel conectado no es ese teléfono.
- La configuración SQL local apunta a `RevisionVisualStarter_Test`; no se mezclaron sus datos con producción. El usuario configurado no tiene acceso a la base productiva.
- Por lo anterior no es posible listar con identidad los 16 drafts ni las 76 fotos sin exportar el diagnóstico/Hive del teléfono afectado. Los totales locales que no puedan demostrarse quedan marcados como **NO DETERMINABLE**.

## Resumen ejecutivo

1. `1134`, `486-2`, `367-2`, `446` y `472-2` no existen en producción y no tienen inspecciones. La ejecución v59 no alcanzó un alta exitosa para ninguno; el auto-create no queda demostrado por estos casos.
2. El 404 de `1134` no puede atribuirse al padrón: el `POST /inspections` desplegado crea el hidrante cuando falta. Sin el evento persistente no se conoce el endpoint exacto.
3. La hipótesis de `serverInspectionId` stale es compatible con el código: cualquier ID local provoca primero `GET /inspections/{id}` y un 404 termina el flujo antes de `_create()`. No está confirmada para 1134 porque v53 mostraba `serverInspectionId=null` y no tenemos el Hive v59.
4. Siete casos históricamente parciales ya convergieron remotamente a `submitted`: 1136 (inspección nueva), 1139, 1296, 414, 430, 431 y 438. También siguen submitted 1142, 1161, 906 y 937 (inspección nueva).
5. Siguen parcialmente sincronizados: 1144 (10/10 fotos, 15 respuestas), 1167 (8 fotos, 12 respuestas), 918 (10/10 fotos, 34 respuestas) y 441 revisión de José (1 foto, 0 respuestas). Todos tienen fotos verificadas remotamente, pero siguen `in_progress`.
6. Home=7 y Sync=16 miden universos distintos. Home agrupa por **hydrantId** y escoge un draft actual; Sync une IDs pendientes de `sync_queue` con todos los drafts no read-only y suma entradas ilegibles. La identidad de los nueve adicionales requiere Hive.
7. Las 76 fotos son registros del usuario en `inspection_photos_v1` cuyo valor en `media_sync_queue` no es exactamente `verified`. La UI no consulta `media_work_queue_v1`, `RvPhotoReference` ni servidor para ese contador.
8. `10/10` significa elementos recorridos/intentos terminados. `syncCompleted` se incrementa aun si el resultado tiene `lastSyncError`; no significa confirmación remota.
9. El active index puede quedar apuntando a una inspección completed: la reconciliación guarda el documento como completed mediante `save()`, pero solo `finalize()` elimina el índice.

## Estado productivo de las cuentas solicitadas

`PV` significa configuración de válvulas parcelarias. El GET administrativo actual no expone `client_inspection_id`, `work_session_id`, PV, claim, conflictId ni rvStatus; se indican como no disponibles, no como ausentes.

| Cuenta | Hidrante | Fuente / activo / alta | Inspecciones (todas) |
|---|---|---|---|
| 1134 | **No existe** | — | Ninguna |
| 486-2 | **No existe** | — | Ninguna |
| 1136 | `98B799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `55C48716...` submitted, rev2, José/RESIDENTE, 57 respuestas, 10/10 fotos verified, GPS+señal; `2B6563CB...` in_progress, rev1, Lorenzo/CUADRILLA AQUAFIM, 0 respuestas/fotos, sin GPS/señal |
| 1139 | `9AB799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `27D3A54D...` submitted, José/RESIDENTE, 59 respuestas, 10/10 verified, GPS+señal |
| 1142 | `9DB799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `9B5FD543...` submitted, 52 respuestas, 10/10 verified, GPS+señal |
| 1144 | `9FB799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `37E15532...` **in_progress**, 15 respuestas, 10/10 verified, GPS+señal |
| 1161 | `ACB799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `77F6E8DA...` submitted, 56 respuestas, 10/10 verified, GPS+señal |
| 1167 | `B0B799EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `0E70E476...` **in_progress**, 12 respuestas, 8/8 verified, GPS+señal |
| 1296 | `11B899EB-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `A0424C7C...` submitted, 58 respuestas, 10/10 verified, GPS+señal |
| 906 | `089190F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `7DBF72E8...` submitted, 57 respuestas, 9/9 verified, GPS+señal |
| 937 | `249190F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `2EEE8CCB...` submitted rev2, José, 54 respuestas, 10/10 verified, GPS+señal; `8CCF53A0...` in_progress rev1, José histórico, 4 respuestas, 4/4 verified, GPS+señal |
| 367-2 | **No existe** | — | Ninguna |
| 446 | **No existe** | — | Ninguna |
| 472-2 | **No existe** | — | Ninguna |
| 441 | `169090F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `A4FD1B20...` submitted rev1, Felipe/CUADRILLA 1, 60 respuestas, 8/8 verified, GPS+señal; `6F333CF2...` in_progress rev2, José/RESIDENTE, 0 respuestas, 1/1 verified, sin GPS/señal |
| 918 | `149190F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `4AA6378A...` **in_progress**, José/RESIDENTE, 34 respuestas, 10/10 verified, GPS+señal |
| 414 | `FB8F90F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `F5315F5C...` submitted, 58 respuestas, 10/10 verified, GPS+señal |
| 430 | `0B9090F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `E3DF5D71...` submitted, 60 respuestas, 10/10 verified, GPS+señal |
| 431 | `0C9090F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `8FFDBC43...` submitted, 58 respuestas, 10/10 verified, GPS+señal |
| 438 | `139090F1-AC8A-F111-9422-0014224FF817` | catalog / sí / 2026-07-28 | `020D397B...` submitted, 60 respuestas, 10/10 verified, GPS+señal |

## 1134 y su 404

### Confirmado

- No existe fila exacta `1134` en el GET administrativo de `rv.hydrants`.
- No existe inspección asociada a 1134.
- Por tanto el intento v59 dejó el servidor en estado **D: nada**.
- El `POST /inspections` del API desplegado no devuelve HYDRANT_NOT_FOUND: dentro de una transacción serializable busca por `normalized_account` y, si no existe, inserta un hidrante `source_type='manual'` y crea la inspección.

### Operaciones 404 posibles antes de tener evidencia local

1. `_synchronizeCatalogs()` puede ejecutar endpoints de catálogos antes de create.
2. Si `serverInspectionId != null`, `GET /inspections/{id}` ocurre antes de `_create()`.
3. Con ID válido, `GET /inspections/{id}/photos` ocurre en reconciliación.
4. Después existen endpoints de contenido, respuestas, válvulas, GPS, señal, upload y submit.

### Inferencia controlada

- Como no se creó ni hidrante ni inspección, el fallo ocurrió antes o durante create.
- Si el draft v59 tiene un `serverInspectionId` stale, la candidata principal es `GET /inspections/{id}` con `INSPECTION_NOT_FOUND`; este flujo impide llegar a auto-create.
- Si conserva `serverInspectionId=null` como en v53, el candidato pasa a ser catálogo previo o `POST /inspections`. En ese caso un 404 del POST demostraría que producción no está ejecutando el código esperado, pero el estado remoto por sí solo no lo prueba.
- El request exacto, requestId, domainCode y clientInspectionId son **NO DETERMINABLES** sin exportar `rv_sync_diagnostics_v1` del teléfono productivo.

## Los 16 diagnósticos pendientes

### Criterio exacto de Sync

```text
pendingIds = cada sync_queue item cuyo status != synced
             salvo draft superseded por estado oficial
pendingIds += cada rvDraftRepository.pending()
              salvo superseded por estado oficial
resultado = pendingIds únicos + sync_queue.unreadableCount
```

`rvDraftRepository.pending()` devuelve todos los documentos accesibles cuyo draft no es read-only. Un documento remoto submitted que no se haya reconciliado localmente sigue entrando.

### Clasificación que sí puede sostenerse

- **Remote submitted / posible local pending:** al menos los 7 casos que cambiaron de parcial a submitted (1136, 1139, 1296, 414, 430, 431, 438). Solo el Hive determina cuáles siguen dentro de los 16.
- **Remote in_progress / local posiblemente pending:** 1144, 1167, 918 y 441 (revisión José).
- **No remote inspection:** 1134, 486-2, 367-2, 446 y 472-2.
- **Stale remote histórico/superseded:** 937 rev1; 1136 rev1 pertenece a otro usuario/cuadrilla y no debe atribuirse al teléfono de José.

Estas categorías forman candidatos, no una asignación uno-a-uno de los 16. El total exacto A–H es **NO DETERMINABLE** sin los 16 `clientInspectionId/serverInspectionId` locales. Afirmar números exactos sería confundir universo servidor con universo Hive.

## Por qué Home muestra 7 y Sync muestra 16

### Home

`RvWorkDashboardProjection.byHydrant()`:

1. agrupa drafts por `hydrantId`;
2. elige el draft actual (primero no read-only, o el más reciente);
3. produce un único grupo por hidrante;
4. cuenta `pendingSync` cuando hay `lastSyncError`, estados locales pendientes/error, partes pendientes/error o cualquier `RvPhotoReference` no verified.

### Sync

Cuenta IDs de cola y de drafts. No agrupa por hidrante y añade entradas de cola sin draft o ilegibles.

### Conclusión

Los nueve de diferencia no pueden identificarse sin Hive. Pueden ser inspecciones adicionales del mismo hidrante, `sync_queue` legacy/orphan o entradas ilegibles. El código confirma la causa estructural de la discrepancia, pero no permite nombrar los nueve desde servidor.

## Las 76 fotografías

### Fuente exacta del contador

```text
accessiblePhotoIds = inspection_photos_v1 del usuario autenticado
pendingPhotos = count(id donde media_sync_queue[id] != 'verified')
verifiedPhotos = count(id donde media_sync_queue[id] == 'verified')
```

La pantalla reporta 492 documentos de foto accesibles: 416 verified + 76 no verified según `media_sync_queue`.

### Reconciliación v59

- `_markPhotoVerified()` actualiza `inspection_photos_v1`, `media_sync_queue` y `media_work_queue_v1` en la misma corrida.
- `_reconcilePhotos()` actualiza además `RvPhotoReference` cuando encuentra identidad directa o hash inequívoco.
- En bootstrap, `MediaReconciliationService` propaga verified de `InspectionPhoto`/`media_sync_queue` a la cola legacy; después `reconcileVerifiedPhotoReferences()` propaga `media_sync_queue` a drafts.
- No se encontró una escritura v59 que degrade explícitamente un `media_sync_queue=verified` a pending durante sync. `retryMedia()` incluso retorna sin modificar si ya está verified.

### Límite

No existe endpoint que relacione las 76 IDs locales con cuenta/inspección; el servidor solo conoce IDs remotos. Sin Hive no se pueden calcular X realmente upload, Y remote verified, Z legacy, W orphan o missing local. Los 10/10 verified de 1144 y 918, y 8/8 de 1167, prueban que existen fotos remotas verificadas en drafts aún in_progress, pero no prueban que estén entre las 76 locales.

## Active inspection index

**Residuo confirmado por código.** `VisualInspectionRepository.finalize()` elimina `active_inspection_index_v1`; `RvDraftRepository.save()` al reconciliar submitted cambia el documento a `InspectionStatus.completed` usando `visualRepository.save()`, que no elimina el índice. Así el índice puede seguir apuntando a un documento completed.

No es fuente directa de `pendingDiagnostics` (este recorre documentos/drafts y sync_queue), pero sí es una inconsistencia persistente y puede influir en `hasLocalInspection/openOrCreate` y reconstrucciones posteriores.

## serverHydrantId linking

- `InspectionRemoteRepository.create()` parsea el response con `_inspection()` y admite `hydrant_id/hydrantId`.
- `_create()` llama `onHydrantResolved(localHydrantId, created.hydrantId)` y persiste `serverHydrantId` en el draft.
- La API `POST /inspections` devuelve `SELECT * FROM rv.inspections`; esa fila contiene `hydrant_id`. Por contrato actual hay información suficiente.
- No puede demostrarse en casos Grupo A porque ninguno llegó a crear hidrante/inspection. El diseño funciona en código, pero su ejecución productiva para esos drafts sigue sin evidencia.

## Qué significa 10/10

`syncTotal = manualHydrants ready + pending drafts`. Después de cada elemento, `syncCompleted++` ocurre aunque haya warning o `lastSyncError`. El contador representa **PROCESS_PROGRESS**, no **SYNC_SUCCESS**. Solo al final se recalculan `pendingCount`, warnings y conflictos para seleccionar `completedWithWarnings`.

## Revisiones repetidas

- 937 conserva rev1 in_progress y rev2 submitted con IDs distintos.
- 441 conserva rev1 submitted de Felipe y rev2 in_progress de José.
- 1136 conserva rev1 in_progress de Lorenzo y rev2 submitted de José.

El servidor conserva ambas inspecciones. La nueva puede llegar submitted (937 y 1136), por lo que la revisión repetida no queda bloqueada; las viejas permanecen como historial/stale.

## Causas raíz restantes y cambios mínimos candidatos para v60

No implementar hasta obtener el diagnóstico local.

1. **Recuperación de serverInspectionId stale:** ante 404 `INSPECTION_NOT_FOUND`, resolver por `clientInspectionId`; si no existe, recrear idempotentemente y conservar auditoría del ID anterior.
2. **Confirmar endpoint del 404 de 1134:** extraer el evento de `rv_sync_diagnostics_v1` antes de decidir el cambio. Si no hay stale ID, verificar que el deployment realmente contiene auto-create y revisar catálogo previo.
3. **Convergencia de submitted:** ejecutar reconciliación GET para cada draft con ID antes de filtrar/omitir errores deterministas; limpiar su sync_queue cuando remoto es final.
4. **Active index:** al guardar transición local a completed, retirar el índice solo si todavía apunta a ese documento, sin borrar el documento.
5. **Contadores:** separar intentados de confirmados y basar el estado final en recuento posterior reconciliado.
6. **Soporte de campo:** exportar desde el teléfono afectado `rv_sync_diagnostics_v1` y un inventario sanitizado de los 16 drafts/76 fotos. Sin este insumo no debe diseñarse una migración de colas por inferencia.

## Respuestas directas

1. 1134 existe: **no**.
2. Tiene inspection: **no**.
3. Status: no aplica.
4. Recurso del 404: **no confirmado**; GET inspection stale es hipótesis condicionada, no hecho.
5. 486-2 existe: **no**.
6. Auto-create funcionó en Grupo A: **no hay evidencia; ninguno fue creado**.
7. Los 16: identidad exacta no disponible sin Hive; candidatos clasificados arriba.
8. Cuántos de los 16 submitted: no determinable; hay al menos siete candidatos remotos recién submitted.
9. Cuántos in_progress: no determinable dentro de los 16; cuatro candidatos actuales en las cuentas revisadas.
10. Cuántos no existen: cinco candidatos Grupo A.
11. Server ID stale: posible y soportado por flujo; no confirmado para 1134.
12. Home 7 vs Sync 16: agrupación por hidrante vs unión de IDs de cola/drafts/ilegibles.
13. Las 76: fotos locales cuyo `media_sync_queue` no es verified.
14. Requieren upload: no determinable sin IDs/Hive.
15. Ya verified remotamente: no determinable por identidad local-remota.
16. Legacy/stale: no determinable sin `media_work_queue_v1` remoto.
17. Active index deja residuos: **sí, confirmado por código**.
18. Linking tiene contrato suficiente: **sí en código**; no ejecutado en Grupo A.
19. 10/10: intentos recorridos, no éxito.
20. Causas restantes: 404 pre-create/stale por confirmar, drafts submitted no reconciliados, registros de cola/índice divergentes y progreso semánticamente ambiguo.
21. Cambios mínimos: los seis candidatos anteriores, condicionados a extraer primero evidencia local.
