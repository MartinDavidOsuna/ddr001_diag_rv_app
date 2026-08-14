# DDR001 RV: alta de hidrantes de campo y revisiones repetidas

Fecha de diseño: 2026-08-13 (America/Hermosillo)

## Línea base auditada

- APP: rama `fix/rv-main-reconciliation-and-map-sync`, HEAD `1fc8ca477b7cf9793a0480169300750caf878f0f` con el working tree staged que compone v58.
- APP `pubspec.yaml`: `0.2.36+58`.
- API: rama `fix/rv-main-reconciliation-and-map-sync`, HEAD `3986d4b43b0b22fcd8889ac670516171c369ba8c`, working tree limpio.
- Pixel 7 Pro `27301FDH3004R7`: `com.aquafim.ddr001diag` `0.2.36 (58)`, `firstInstallTime=2026-08-08 00:17:40`.
- No se borraron datos, no se modificó producción y no se instaló software durante esta auditoría.

## 1. Flujo actual de nueva revisión

`Inicio -> Nueva revisión visual -> NewSurveyPage -> búsqueda en catalogHydrants -> confirmación -> RvDraftRepository.openOrCreate`.

La pantalla actual solo permite tocar un hidrante si `availableForRv=true`. Si ya fue revisado, navega al reporte visual en lugar de ofrecer una nueva revisión. Esto impide la revisión repetida desde esta UX.

## 2. Estado de "Ingresar manualmente"

La capacidad no desapareció del código, pero quedó presentada condicionalmente como `Registrar hidrante no encontrado`: solo aparece cuando hay texto de búsqueda o cero coincidencias. El requisito operativo pide una acción permanente y explícita `INGRESAR MANUALMENTE`.

`AppState.createManualHydrant` ya genera un UUID local, persiste dos proyecciones Hive (`mine`/`all`) y encola `manualHydrant`. Es offline-first y no debe sustituirse.

## 3. Historia recuperada

- `7698576` contenía selección de catálogo, sin alta manual.
- `0cf6c95` introdujo `Registrar hidrante no encontrado`, formulario local y `createManualHydrant`.
- La rama actual conserva esa implementación reducida (cuenta y motivo), pero su visibilidad condicional hace que el técnico no la perciba como flujo primario.

Se reutilizará el mecanismo actual y no se creará una UX paralela.

## 4. Modelo actual de hidrante

`rv.hydrants` ya distingue hidrantes importados y de campo mediante:

- `source_type` (`catalog` / `manual`);
- `created_by_user_id`;
- `created_in_crew_id`;
- `local_reference`;
- `source_environment`;
- `manual_reason`;
- timestamps existentes.

No se requieren columnas nuevas para trazabilidad básica.

## 5. Alta manual existente

`POST /hydrants/manual` crea un hidrante manual, pero actualmente:

- responde 409 ante una cuenta exacta ya existente;
- trata cercanía geográfica como conflicto bloqueante;
- no devuelve el existente por `localReference` desde el propio handler;
- no recupera drafts históricos que nunca fueron marcados como `manualHydrant` y llegan directamente a `POST /inspections`.

Por ello no basta con reparar solamente la cola `manualHydrant`.

## 6. Constraints SQL

- Existe un índice único filtrado por `(created_by_user_id, local_reference)` cuando `local_reference IS NOT NULL`.
- `normalized_account` se compara con `UPPER(LTRIM(RTRIM(account)))`; esta normalización conserva guiones y sufijos.
- Debe verificarse/mantenerse una garantía única de cuenta normalizada para evitar dos altas simultáneas. Si el esquema productivo no la tiene, la serialización y el manejo de violación 2601/2627 deben devolver la fila ganadora sin perder la solicitud.

## 7. Conflictos actuales

La primera inspección completa adquiere un claim oficial. Una segunda inspección del mismo hidrante se persiste con `status='conflict'`, crea `rv.inspection_conflicts` y devuelve `result='conflict'`. La APP transforma esto en `RvLocalStatus.conflict`, aunque toda la evidencia ya esté guardada.

El conflicto es administrativo. El técnico debe ver la segunda captura como enviada. Se conservará `inspection_conflicts`, el claim oficial anterior y la señal administrativa, pero la proyección local final será enviada. La API debe representar que la captura fue recibida sin destruir la conciliación.

## 8. Segunda inspección

`rv.inspections` ya separa identidad de hidrante e inspección y `client_inspection_id` permite múltiples inspecciones con UUID distintos. La barrera está en la elegibilidad UI y en la semántica de submit/claim, no en el modelo relacional base.

## 9. Estrategia idempotente elegida

Se integrará el `ensure` dentro de `POST /inspections`, en la misma transacción serializable de creación:

1. Resolver primero por `(clientInspectionId, user)`; si ya existe, devolver la misma inspección.
2. Buscar la cuenta exacta normalizada, conservando guiones.
3. Si no existe, crear `rv.hydrants` como `manual`, con usuario, cuadrilla, `local_reference=clientInspectionId`, ambiente y motivo técnico de recuperación.
4. Crear la inspección asociada dentro de la misma transacción.
5. Auditar el alta automática.
6. Ante concurrencia, volver a leer la cuenta normalizada y usar la única fila ganadora.

Esta opción recupera tanto nuevas altas offline como drafts v53/v58 (`1134`, `486-2`, `367-2`, `446`, `472-2`) sin exigir que tengan una entrada previa en la cola manual. También cubre pérdida de respuesta: el reintento por `clientInspectionId` devuelve la misma inspección y el mismo hidrante.

La respuesta de create expondrá el `hydrant_id` ya presente en la fila de inspección. La APP persistirá la equivalencia local-remota usando el `remoteId` existente del hidrante cacheado, conservando el UUID local para localizar el draft y las fotografías.

## Compatibilidad y rollback

- No se eliminan cajas Hive ni campos existentes.
- Los drafts v58 se leen sin migración destructiva.
- Los endpoints existentes se mantienen; la ampliación de `POST /inspections` es compatible.
- Rollback APP: reinstalar la build anterior con `adb install -r`; los datos nuevos permanecen legibles.
- Rollback API: revertir handler/migración antes de desplegar; los hidrantes manuales ya creados deben conservarse como evidencia y nunca borrarse.
- Riesgo principal: cuentas históricas ambiguas. Se mitiga creando identidad exacta independiente y dejando la conciliación al administrador, sin equivalencias automáticas.

## Validación requerida

- API: existente, inexistente, retry, concurrencia, `486` != `486-2`, trim, guiones, autorización, auditoría y trazabilidad.
- APP: entrada manual visible, offline, resolución online, recuperación de cinco fixtures, pérdida de respuesta, persistencia tras restart y revisión repetida enviada.
- Circuit breaker: conservar la política v58 y mostrar el motivo real de pausa; un 404 determinista no debe pausarlo.
- No se generará/distribuirá APK ni se tocará producción sin autorización posterior.

## Implementación local realizada

- `POST /inspections` asegura el hidrante exacto dentro de la transacción serializable y crea el hidrante `manual` cuando falta.
- `POST /hydrants/manual` ahora es ensure idempotente: resuelve por referencia local o cuenta exacta; una coincidencia geográfica queda en auditoría y no bloquea al técnico.
- La APP persiste `serverHydrantId` opcional en el draft y `remoteId` en la proyección del hidrante, sin cambiar el UUID local.
- La acción `INGRESAR MANUALMENTE` es siempre visible y conserva el flujo offline existente.
- Un documento completado ya no se reutiliza: se conserva y el índice activo apunta a una nueva inspección.
- Una segunda inspección se almacena como `submitted`; `rv.inspection_conflicts` y `hydrant_rv_status.has_conflict` conservan la conciliación administrativa.
- Los 404 de inspección y foto exponen domain codes distintos y la APP conserva su contexto HTTP.
- La pausa global muestra ahora el motivo sistémico clasificado.

## Resultados de validación local

- `flutter analyze`: verde, sin hallazgos.
- `flutter test`: 361 pruebas verdes.
- API `npm run lint`: verde.
- API `npm run type-check`: verde.
- API `npm run build`: verde.
- API `npm test`: 216 pruebas verdes.
- Integración SQL: el bloque nuevo ejecutó alta, retry, cuentas con/sin sufijo y concurrencia antes de que la suite heredada se detuviera en un endpoint posterior porque la base `RevisionVisualStarter_Test` no contiene `rv.hydrant_rv_status`. La base productiva no fue modificada.

## Validación Pixel pendiente y justificada

No se instaló esta revisión en el Pixel todavía: el dispositivo está configurado contra producción y la API productiva no contiene el cambio local. Instalar y ejecutar sincronización antes de disponer de un API de prueba compatible volvería a producir el 404 o podría escribir datos productivos, contrario a las reglas de seguridad. La validación `adb install -r` debe hacerse con una versión inequívoca y un API de prueba con esquema completo, o después de autorizar el despliegue API.
