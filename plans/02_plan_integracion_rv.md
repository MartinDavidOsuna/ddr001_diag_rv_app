# Plan de integración RV

Fecha: 2026-07-22  
Base: auditoría real de la app RV, app completa y API RV local.

## 1. Alcance

Entregar el flujo único registro de campo → hidrantes → borrador RV → checklist/GPS/señal/fotos → sincronización → submit, con persistencia offline y mensajes en español. La API y SQL Server permanecen sin cambios. F02-B/RF se oculta mediante una configuración de producto y rutas, sin eliminación destructiva.

## 2. Decisiones de arquitectura

- Mantener Provider/`AppState` para minimizar el cambio, pero extraer sesión, API y sincronización a servicios/repositorios inyectables.
- Mantener Hive CE, codec versionado, journal, recuperación, cuarentena y colas.
- Incorporar una capa `data/remote` con Dio central y DTO/mappers explícitos; no filtrar JSON de API hacia widgets.
- Tratar el estado local como fuente de verdad durante captura; la red confirma y actualiza estado remoto.
- Guardar access/refresh token y session ID en `flutter_secure_storage`; conservar `installationId` persistente (secure storage o preferencia no sensible) creado una sola vez con UUID.
- Configurar `API_BASE_URL` en un único `AppConfig.fromEnvironment`, con valor local de desarrollo y validación de URL.
- Añadir excepción HTTP solo a Android debug. Release no tendrá cleartext global.
- Restaurar primero plataformas nativas desde `DDR001_DIAG`, verificando un diff acotado y los identificadores `com.aquafim.ddr001diag`.

## 3. Reutilización

Se reutilizan con adaptación:

- `AppTheme`, widgets comunes y estructura visual de lista/detalle.
- `VisualInspectionRepository` y documentos JSON versionados.
- `SyncQueueRepository`, `OperationJournalRepository`, recuperación, cuarentena e integridad.
- `ReliablePhotoService`, procesamiento/compresión/hash/miniaturas, reconciliación y escaneo de huérfanos.
- `LocationService` y captura de señal/conectividad disponible.
- Pantalla de sincronización, badges y etiquetas de estado.
- Pruebas y helpers Hive actuales.

No se reutilizan como fuente de datos: login demo, `MockAssignmentSyncService`, `demo_data.dart`, checklist hardcodeado ni transporte de sincronización simulado.

## 4. Módulos nuevos

1. Configuración y HTTP: `AppConfig`, `ApiClient`, modelo `ApiProblem`, interceptor Bearer/request ID, refresh de campo con exclusión mutua y logs debug redactados.
2. Sesión: DTOs/repositorio local seguro/remoto, instalación y captura de datos del dispositivo.
3. Hidrantes: DTO, mapper, remoto paginado y caché Hive.
4. Checklist: DTOs dinámicos, repositorio con ETag/304 y caché versionada.
5. Inspección API: crear/consultar/respuestas/GPS/señal/fotos/submit/cancel.
6. Sincronización: coordinador determinista con dependencias, límite de intentos y backoff; acción manual.
7. Renderizador de checklist para los 11 tipos reales y dependencias reales.

## 5. Modelos locales

### Sesión de campo

`FieldSession`: `sessionId`, usuario (`name`, `email`, `phone`), `crew`, `installationId`, `startedAt`, estado. Tokens se almacenan por separado y de forma segura.

### Hidrante cacheado

Mapear únicamente: `hydrantId`, `accountNumber`, `installationYear`, `flowLps`, `sourceX`, `sourceY`, `sourceCrs`, `latitude`, `longitude`, `locality`, `municipality`, `metadataJson`, `calculatedStatus`, `distanceKm` cuando exista, más timestamps de caché.

### Checklist cacheado

`id`, `code`, `version`, `title`, `publishedAt`, secciones/items, ETag y fecha de actualización. Item: identificadores, código, label, tipo, required, orden, unidad, opciones, dependencia, `photoSlot`, ayuda.

### Borrador RV

Extender/adaptar el documento visual existente con `clientInspectionId`, `serverInspectionId`, `accountNumber/hydrantId`, `sessionId`, `checklistId/version`, `localStatus`, `remoteStatus`, timestamps, respuestas tipadas, muestra GPS, muestra de señal, referencias de fotos/slots, errores, intentos y marcas de sincronización. Estados: `draft`, `pendingSync`, `syncing`, `synced`, `submitPending`, `submitted`, `syncError`.

## 6. Flujo de sincronización

```text
borrador local
  → crear/recuperar inspección por clientInspectionId
  → PUT lotes de respuestas
  → POST muestra GPS
  → POST muestra señal
  → POST cada foto por photoId + SHA-256
  → comprobar requerimientos locales
  → POST submit solo por acción final del usuario
```

Cada mutación se guarda localmente antes de encolarse. Las operaciones usan una clave estable derivada de entidad/versión, salvo foto, que usa `photoId` y hash. Al reiniciar se recuperan trabajos no confirmados. Backoff sugerido: 5 s, 15 s, 45 s, 2 min, 5 min; máximo automático por ciclo y reinicio mediante acción manual. Errores 4xx de dominio no se reintentan sin cambio de datos; 401 intenta una sola rotación coordinada; 409 se reconcilia consultando el recurso; 5xx/timeouts quedan pendientes.

## 7. Estrategia offline

- Abrir con la última sesión utilizable y datos cacheados; no invalidar un borrador por falta de red.
- Hidrantes y checklist muestran antigüedad de caché.
- `If-None-Match` evita reemplazar checklist sin cambios; una inspección conserva su versión aunque se publique otra.
- Captura de respuesta/GPS/señal/foto confirma primero `Guardado localmente`.
- Las fotos no se eliminan hasta respuesta `verified` y reconciliación; aun verificadas se retienen según política local explícita.
- Estados visibles: guardado local, pendiente, sincronizando, sincronizado, error, enviado.
- `Sincronizar ahora` procesa una sola instancia del coordinador y evita dobles pulsaciones.

## 8. Etapas

### Etapa 0 — plataforma e identidad

Restaurar `android/` e `ios/` desde la app completa; verificar identificadores/nombre/versión/permisos; añadir cleartext solo debug y confirmar que no se incorporan firmas ni secretos.

### Etapa 1 — configuración, cliente y sesión

Agregar dependencias seguras, `AppConfig`, Dio, errores/refresh/request ID, installation ID y formulario real de campo. Dado que no hay catálogo field de cuadrillas, implementar texto validado conforme al contrato y dejar registrada la decisión; no inventar opciones.

### Etapa 2 — hidrantes y checklist

Implementar descarga/búsqueda/detalle/caché y checklist activo con ETag. Añadir DTOs, mappers y pruebas contractuales con fixtures tomados del código API.

### Etapa 3 — borrador/renderizado

Adaptar inspección visual local al checklist dinámico; validar tipos, dependencias, obligatoriedad y no aplica. Mantener autosave y recuperación.

### Etapa 4 — evidencia

Integrar GPS, señal y siete slots fotográficos obligatorios con el borrador y cola. Conectar multipart real con hash y verificación.

### Etapa 5 — sincronización y submit

Implementar coordinador ordenado, refresh, idempotencia, backoff, reconciliación y envío final. Mostrar errores 422 por item/slot.

### Etapa 6 — simplificación y certificación

Ocultar F02-B/RF y navegación no necesaria por feature flag; probar cierre/reapertura, modo avión, pérdida de conexión, dobles pulsaciones, proceso muerto, actualización de checklist y build Android debug/release sin secretos.

## 9. Pruebas previstas

- Unitarias: configuración, parsing RFC 7807, redacción de logs, refresh único, DTO/mappers, dependencias, ETag, estados/backoff e idempotencia.
- Repositorios: sesión segura, caché de hidrantes/checklist, migración de documento RV y reapertura.
- Widget: formulario de campo, errores en español, render de cada tipo real, progreso, slots y estados de sync.
- Integración con servidor falso: 201/304/401+refresh/409/422/5xx, multipart, reintento y submit.
- Offline: crear, responder, capturar fotos, cerrar proceso, reabrir y sincronizar.
- Contrato manual real: API local `http://192.168.1.111:3000/api/v1` desde dispositivo Android en la misma red.
- Regresión: `flutter analyze`, `flutter test` y pruebas existentes; build APK debug y release cuando se restaure plataforma/firma disponible.

## 10. Criterios de aceptación

- Identidad nativa exacta y release sin cleartext global ni secretos versionados.
- Sesión real con tokens seguros y refresh funcional.
- `installationId` estable tras reinicio.
- Hidrantes/checklist disponibles offline después de primera descarga; ETag/304 probado.
- Borrador y fotos sobreviven cierre forzado.
- No se crean inspecciones ni fotos duplicadas ante doble toque/reintento.
- Los once tipos reales se interpretan; solo se renderizan controles respondibles.
- GPS/señal degradan con explicación y el submit comunica requisitos faltantes.
- Siete fotos se comprimen, hashean, suben y verifican.
- Sincronización manual observable y limitada; submit termina en `submitted` y el dashboard puede leer los datos.
- No aparece contenido F02-B/RF.
- Analyze y suite completa pasan.

## 11. Riesgos y decisiones pendientes

- La restauración nativa es prerrequisito y debe preservar firma externa.
- Cuadrilla es texto libre según API; si negocio exige catálogo, se necesita primero un endpoint field. No modificar API sin autorización.
- La UI existente no mapea uno-a-uno con el checklist dinámico; se prioriza contrato y reutilización visual, no compatibilidad de cada modelo hardcodeado.
- Revisar con el equipo API la lectura de inspección sin filtro de propietario y la documentación OpenAPI incompleta.
- El submit fija siete slots aunque el checklist también puede contener items `photo`; el cliente debe tratar los slots de API como requisito canónico.

## 12. Lista exacta propuesta de archivos para la siguiente etapa

La lista inicial se limita a Etapas 0–2; etapas posteriores se concretarán tras validar fixtures y migración:

### Restaurados desde `DDR001_DIAG` y revisados

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/debug/AndroidManifest.xml`
- `android/app/src/main/res/values/strings.xml`
- `android/app/src/main/kotlin/com/aquafim/ddr001diag/MainActivity.kt`
- `android/app/src/main/kotlin/com/aquafim/ddr001diag/CellularInternetProbeChannel.kt`
- `android/build.gradle.kts`
- `android/settings.gradle.kts`
- `android/gradle.properties`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/SceneDelegate.swift`
- archivos estándar de workspace, assets y configuración Flutter contenidos actualmente en `DDR001_DIAG/ios`

### Modificados

- `pubspec.yaml`
- `lib/app/bootstrap.dart`
- `lib/app/router/app_router.dart`
- `lib/core/services/app_state.dart`
- `lib/features/auth/auth_pages.dart`
- `lib/features/hydrants/hydrant_pages.dart`
- `lib/features/shell/main_shell.dart`
- `lib/features/sync/sync_page.dart`
- `.gitignore` (solo si faltan exclusiones de secretos nativos/configuración)

### Nuevos

- `lib/core/config/app_config.dart`
- `lib/core/network/api_client.dart`
- `lib/core/network/api_problem.dart`
- `lib/core/network/request_id_interceptor.dart`
- `lib/core/network/token_refresh_interceptor.dart`
- `lib/core/storage/secure_session_store.dart`
- `lib/core/device/installation_service.dart`
- `lib/features/auth/data/field_session_models.dart`
- `lib/features/auth/data/field_session_repository.dart`
- `lib/features/hydrants/data/hydrant_api_models.dart`
- `lib/features/hydrants/data/hydrant_repository.dart`
- `lib/features/checklist/data/checklist_models.dart`
- `lib/features/checklist/data/checklist_repository.dart`
- `test/core/app_config_test.dart`
- `test/core/api_client_test.dart`
- `test/auth/field_session_repository_test.dart`
- `test/hydrants/hydrant_repository_test.dart`
- `test/checklist/checklist_repository_test.dart`

No se proponen cambios en `DDR001_API_RV`, sus scripts SQL ni `DDR001_DIAG`.

## 13. Avance ejecutado en `feature/rv-foundation` (2026-07-22)

Las Etapas 0–2 quedaron implementadas: plataformas nativas restauradas sin secretos, configuración central, Dio autenticado con refresh rotativo, sesión de campo segura, `installationId`, hidrantes cache-first, checklist dinámico con ETag/304 y flag RV-only. La suite pasó de 85 a 101 pruebas y se generó APK debug. El flujo de respuestas, evidencia y submit permanece deliberadamente para la etapa siguiente. Véase `plans/03_implementacion_base_rv.md` para evidencia, comandos y riesgos.
