# Etapa 12.5.5 — Conectividad, catálogo y alta manual

Fecha de inicio: 2026-07-28  
Rama conservada: `feature/rv-crs-and-catalog-resolution`

## Versionado

- Versión real encontrada antes de esta etapa: `0.2.1+14`.
- Primera APK correctiva: `0.2.2+15`.
- Entrega final destinada a producción, sin reutilizar `versionCode`:
  `0.2.3+16`.
- Identificadores Android/iOS: no se modifican.

## Ambiente autorizado de trabajo

- App: `development` o `test`.
- API de prueba: valor inyectado mediante `API_BASE_URL`.
- Producción no se usa para pruebas ni se modifica.

## Flujo encontrado antes de modificar código

```text
Flutter main/bootstrap
→ AppConfig.fromEnvironment
→ Dio ApiClient
→ restauración de FieldSession
→ AppState.initialize
→ AppState.synchronizeAssignments
→ GET /hydrants?scope=all
→ GET /hydrants?scope=mine
→ GET /profile/today-stats
→ HydrantRepository
→ Hive local_hydrants_v1
→ AppState.catalogHydrants / AppState.hydrants
→ HydrantsPage / NewSurveyPage
```

### URL y transporte

- La URL se resuelve centralmente en `lib/core/config/app_config.dart`.
- Desarrollo requiere una URL explícita mediante `API_BASE_URL`.
- El endpoint configurado previamente para producción es
  `http://cifra.aquafim.com:3002/api/v1`.
- Android usa una excepción de cleartext limitada por Network Security Config;
  no existe `usesCleartextTraffic=true` global.
- Prefijo esperado: `/api/v1`.

### Cliente HTTP encontrado

- `connectTimeout`: 15 s.
- `sendTimeout`: 25 s.
- `receiveTimeout`: 25 s.
- Interceptor de `X-Request-ID`.
- Interceptor de token Bearer.
- Un refresh rotativo compartido después de 401.
- Sin reintentos GET limitados.
- Sin medición de duración/tamaño/origen.
- Sin health check global.
- Sin deduplicación general de GET; solo existe exclusión booleana en
  `synchronizeAssignments`.

### Peticiones al restaurar una sesión conectada

1. `GET /field-sessions/current`.
2. `GET /hydrants?scope=all`, paginado.
3. `GET /hydrants?scope=mine`, paginado.
4. `GET /profile/today-stats`.
5. `GET /checklists/RV/active`.
6. Las consultas de catálogos dinámicos se realizan según el flujo de la app.

Las tres consultas del punto 2 al 4 son secuenciales. Cada hidrante se escribe
en Hive con un `await box.put` individual.

## Causas raíz iniciales

### 1. Indicador permanente “Sin conexión”

`AppState.synchronizeAssignments` convierte **cualquier** `ApiException` en
`online=false`. Por tanto, 401, 403, 404, 422, 429, 500, timeout, error de
parsing o fallo de una consulta secundaria se presentan como ausencia de red.
No hay un modelo separado para interfaz, Internet y API. Tampoco existe
revalidación en `AppLifecycleState.resumed`.

### 2. Comunicación lenta

- Carga secuencial de catálogo general, lista personal y estadísticas.
- Hasta dos recorridos paginados del mismo conjunto.
- Escritura Hive por registro en lugar de un lote.
- La pantalla espera el flujo completo para reflejar éxito.
- Timeouts de consulta JSON mayores que el objetivo de campo.
- No existe instrumentación segura de duración ni deduplicación dentro del
  repositorio.

### 3. Catálogo no visible

- `scope=all` sí consulta `rv.hydrants` activos.
- `scope=mine` no consulta una tabla de asignaciones: filtra hidrantes que ya
  tengan una inspección del usuario (`latest.inspection_id IS NOT NULL`).
- Un usuario nuevo recibe naturalmente cero elementos personales aunque haya
  catálogo general.
- El parser acepta `snake_case` para ID y cuenta, pero los alias de estado
  difieren entre API y cliente.
- Una falla posterior en `today-stats` invalida visualmente toda la operación.
- La caché no se reconcilia: elementos retirados/inactivos permanececen.

### 4. Alta manual no disponible

- `HydrantsPage` oculta su FAB cuando `AppConfig.rvOnly == true`.
- `NewSurveyPage` obliga a seleccionar un elemento de `catalogHydrants`.
- No existe modelo persistido de hidrante manual, formulario, endpoint
  `/hydrants/manual` ni reconciliación de ID.
- La cola ya soporta propietario, cuenta, ambiente, dependencias e
  idempotency key, por lo que puede reutilizarse sin borrar datos existentes.

## Archivos involucrados

### Flutter

- `lib/core/config/app_config.dart`
- `lib/core/network/api_client.dart`
- `lib/core/network/api_exception.dart`
- `lib/core/services/app_state.dart`
- `lib/app/app.dart`
- `lib/app/bootstrap.dart`
- `lib/features/hydrants/data/hydrant_repository.dart`
- `lib/features/hydrants/data/hydrant_api_models.dart`
- `lib/features/hydrants/hydrant_pages.dart`
- `lib/features/hydrants/new_survey_page.dart`
- `lib/data/local/sync_queue_repository.dart`
- pruebas bajo `test/`

### API

- `src/modules/api.routes.ts`
- `src/http/middleware.ts`
- `src/modules/idempotency/idempotency.middleware.ts`
- `database/01_revision_visual_starter_SQL2014.sql`
- nueva migración y diagnóstico 12.5.5
- pruebas unitarias e integración bajo `tests/`

## Cambio propuesto

1. Modelo reactivo por capas: interfaz, acceso efectivo, API live y API ready.
2. Health checks deduplicados, con enfriamiento y revalidación al reanudar.
3. Clasificación de HTTP independiente del estado de red.
4. Timeouts JSON 10/30/30 e instrumentación segura.
5. Solicitudes de catálogo deduplicadas y caché mostrada antes del remoto.
6. Escritura/reconciliación Hive por lote y conservación ante fallos.
7. Estado vacío explícito para usuario sin asignaciones.
8. Alta manual local con UUID, propietario y ámbito; inspección inmediata y
   cola dependiente.
9. Endpoint idempotente de alta manual con identidad tomada del token,
   auditoría y conflicto controlado.
10. Diagnóstico SQL únicamente de lectura para la base de pruebas.

## Riesgos

- El modelo SQL actual no tiene tabla explícita de asignaciones ni columnas de
  propietario/origen manual en `rv.hydrants`; requiere una migración aditiva.
- La reconciliación de IDs debe conservar referencias históricas y no puede
  reescribir documentos parcialmente sin una operación transaccional local.
- HTTP sigue siendo temporal e inseguro; debe migrarse a HTTPS.
- La validación física de API caída requiere detener solo la API local de
  pruebas, nunca producción.

## Pruebas previstas

- Pruebas Flutter de estados, lifecycle, deduplicación, caché, parsing, alta
  manual, aislamiento, cola, conflicto e idempotencia.
- `dart format lib test`, `flutter analyze`, `flutter test`,
  `flutter build apk --debug`.
- API: lint, type-check, unitarias, integración SQL autorizada y build.
- `adb install -r` y validación no destructiva en Pixel.

## Resultado físico

### Resultado final automatizado

- Flutter: 166 archivos formateados, cero cambios de formato; `flutter
  analyze` sin hallazgos; 233/233 pruebas aprobadas.
- APK debug: construida para `development` con URL inyectada.
- API: Node `22.23.1`; lint, type-check, 85/85 pruebas unitarias, 12/12
  pruebas de integración SQL (6 archivos) y build aprobados.
- La integración se ejecutó serialmente para evitar que fixtures SQL
  independientes compitieran por los mismos recursos.
- Diagnóstico SQL ejecutado únicamente en `RevisionVisualStarter_Test`:
  1,169 hidrantes, 1,169 activos, cero manuales residuales, cero duplicados
  exactos y cero huérfanos devueltos por las consultas. Consulta agregada:
  31 ms, 182 lecturas lógicas; búsqueda geográfica: 8 ms.
- `health/live`, cinco muestras desde la estación: 858 ms en el primer
  arranque y 17–20 ms en caliente.
- `health/ready`, cinco muestras: 32–135 ms.
- El Pixel confirmó conectividad TCP directa al endpoint inyectado.

### Instalación física

- Dispositivo: Pixel 7 Pro, serie `27301FDH3004R7`.
- Instalación: `adb install -r`, resultado `Success`.
- Antes: `versionName=0.2.1`, `versionCode=14`.
- Después: `versionName=0.2.2`, `versionCode=15`.
- `firstInstallTime` permaneció en `2026-07-24 13:39:51`, evidencia de
  actualización en sitio, sin desinstalación ni limpieza.
- Fecha de actualización: `2026-07-28 15:33:47` (America/Hermosillo).
- Se confirmó que siguen presentes Hive, fotografías/colas y almacenamiento
  seguro. La APK no se abrió contra test porque existe almacenamiento seguro
  persistido de la entrega anterior: hacerlo con credenciales de otro ambiente
  podía invalidar la sesión, contrario a la prohibición de eliminar sesiones.
  Por esa razón los casos físicos A–F que requieren interacción autenticada
  quedan pendientes de una cuenta/sesión de pruebas dedicada. Las capas,
  lifecycle, errores HTTP, deduplicación, caché, alta manual, aislamiento e
  idempotencia quedaron cubiertos por pruebas automatizadas.

## Implementación final

- Estados: `checking`, `noNetwork`, `internetAvailable`, `apiUnavailable` y
  `apiAvailable`; el pendiente de sincronización se presenta de forma
  independiente.
- El monitor combina interfaz activa y `GET /health/live`, deduplica
  comprobaciones, aplica enfriamiento y revalida en `resumed`.
- 401, 403, 422 y 500 ya no alteran el estado de red. Timeout y servidor no
  disponible conservan mensajes específicos.
- Timeouts JSON finales: conexión 10 s, envío 30 s y recepción 30 s.
- Solo GET idempotentes reciben un reintento limitado; ninguna escritura se
  reintenta automáticamente.
- Catálogo general, personal y estadísticas se solicitan en paralelo. Las
  páginas idénticas activas se deduplican y la caché se escribe por lote.
- La caché visible no se borra ante fallos; una respuesta completa reconcilia
  altas/cambios/bajas remotas y conserva altas manuales.
- Alta manual: UUID local estable, propietario/cuenta/ambiente, persistencia
  inmediata, inspección local, cola dependiente y sincronización idempotente.
- `POST /api/v1/hydrants/manual` obtiene identidad del token, valida permisos
  y coordenadas, audita, detecta cuenta/coordenadas potencialmente duplicadas,
  devuelve conflicto controlado y enlaza el ID remoto sin perder el local.
- Catálogo API expone registros de catálogo y únicamente las altas manuales
  propias; el aislamiento local usa el namespace de usuario/cuenta/ambiente.

## Riesgos pendientes

- El transporte productivo continúa en HTTP. La excepción Android está
  limitada al host, pero debe migrarse a HTTPS con certificado válido.
- No existe todavía una entidad explícita de asignación de hidrantes; `mine`
  conserva la semántica de inspeccionados propios más altas manuales propias.
- El formulario manual captura identificación, localidad/módulo y motivo; las
  coordenadas y fotografías se capturan en la inspección inmediata, no en el
  diálogo inicial.
- La medición física completa A–F requiere una sesión dedicada al ambiente de
  pruebas para no arriesgar la sesión persistida actual.
