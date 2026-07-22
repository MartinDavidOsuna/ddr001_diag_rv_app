# Auditoría inicial de DDR001_DIAG_RV_APP

Fecha: 2026-07-22  
Alcance: inspección de `DDR001_DIAG_RV_APP`, `DDR001_DIAG` y `DDR001_API_RV`, sin cambios funcionales, de API ni de base de datos.

## 1. Repositorios y estado Git

| Proyecto | Ruta absoluta | Rama | Remoto | Último commit | Estado inicial |
|---|---|---|---|---|---|
| App RV | `C:\DEV\AQAGS\ddr001_diag_rv_app` | `main` | `https://github.com/MartinDavidOsuna/ddr001_diag_rv_app.git` | `0dff202 Versión base RV derivada de la app completa` | Limpio |
| App completa (referencia) | `C:\DEV\AQAGS\ddr001_diag` | `main` | `https://github.com/MartinDavidOsuna/ddr001_diag_app.git` | `3c186de fix: last version before RV dedicated app all issues solved` | Limpio |
| API RV (fuente de verdad) | `C:\DEV\AQAGS\ddr001_api_rv` | `main` | `https://github.com/MartinDavidOsuna/ddr001_api.git` | `345448f feat: complete tested RV inspection API flow` | Limpio |

La documentación se creó sobre `main` por ser el único cambio autorizado en esta etapa. Antes de la integración funcional se recomienda crear `feature/rv-api-integration` desde `main`.

## 2. Herramientas, versión e identidad

- Flutter `3.44.5` stable, framework `f94f4fc76b`.
- Dart `3.12.2`; DevTools `2.57.0`.
- `pubspec.yaml`: paquete `ddr001diag`, versión `0.2.0+3`, descripción del diagnóstico DDR001.
- Título Material real: `DIAGNOSTICO HIDRANTES`.
- **Bloqueo nativo en la app RV:** no existen `android/` ni `ios/`. Por ello la app RV no tiene hoy `build.gradle(.kts)`, manifests, `project.pbxproj` ni `Info.plist` propios que permitan verificar o compilar sus identificadores.
- Referencia verificada en la app completa: Android `namespace` y `applicationId` = `com.aquafim.ddr001diag`; iOS `PRODUCT_BUNDLE_IDENTIFIER` = `com.aquafim.ddr001diag`; `CFBundleDisplayName`, `CFBundleName` y recurso Android `app_name` corresponden a `DIAGNOSTICO HIDRANTES`; versión `0.2.0+3`.
- No se inspeccionó ni modificó material de firma, y no se generaron llaves.

Los identificadores de la app completa son evidencia de referencia, no valores efectivos de la app RV mientras falten los proyectos nativos. La recuperación mínima debe copiar/restaurar los directorios nativos versionados de la app completa y revisar el diff antes de cualquier build, conservando identificadores y firma.

## 3. Estructura y arquitectura Flutter actuales

La app RV es, en su código Dart actual, una derivación prácticamente completa de `DDR001_DIAG`, no una app RV ya recortada.

- Organización por capas y features: `lib/app`, `lib/core`, `lib/domain`, `lib/data`, `lib/features`.
- Arranque: `main.dart` → `app/bootstrap.dart` → `DiagnosticApp`.
- Estado: `Provider` con un `AppState extends ChangeNotifier` monolítico.
- Navegación: `go_router`, `StatefulShellRoute.indexedStack`, ramas Inicio/Hidrantes/Mapa/Perfil y ruta global de sincronización.
- Tema y widgets: Material, `AppTheme`, `common_widgets.dart`; identidad visual reutilizable.
- El router aún importa y expone `FunctionalInspectionPage` para tipo `b`; también permanecen modelos, catálogos, cajas Hive, pantallas y pruebas F02-B/RF.
- Inicio de sesión actual: demo local con correo/contraseña fija; `authenticated` se basa en `SharedPreferences` (`demo_session`). No existe sesión REST de campo.
- Datos de hidrantes/asignaciones: `MockAssignmentSyncService` y datos demo; no existe repositorio REST real de hidrantes.
- Dio solo aparece de forma aislada en el servicio de actualización APK. No existe cliente API central, configuración `API_BASE_URL`, interceptores de auth ni mapeo RFC 7807.
- `flutter_secure_storage` no figura como dependencia.

## 4. Persistencia local y recuperación

La base offline es reutilizable y sólida, aunque requiere adaptar entidades al contrato API:

- Hive CE + documentos JSON versionados.
- Cajas para inspecciones visuales, índice activo, hidrantes locales, fotografías, colas de medios y sincronización, trazas, revisiones, journal, cuarentena e informes de integridad.
- `VisualInspectionRepository` con documento e índice.
- `SyncQueueRepository` con dependencias, intentos y estados.
- `OperationJournalRepository`, `RecoveryCoordinator`, `IntegrityAuditService`, `QuarantineRepository`.
- `MediaReconciliationService`, `OrphanMediaScanner` y regeneración de miniaturas.
- `SharedPreferences` para preferencias y sesión demo; no apropiado para tokens.

No hay todavía caché local del checklist dinámico/ETag, sesión/token segura ni modelo local que relacione de forma explícita `clientInspectionId` con `serverInspectionId` y el estado remoto.

## 5. Medios, GPS y conectividad

### Medios

`ReliablePhotoService`, `ImageProcessingService`, `InspectionPhoto`, cola de trabajo y reconciliación ya cubren captura cámara/galería, copia durable, compresión, hash, miniatura, journal y recuperación. Deben conservarse y conectarse al multipart real. El modelo actual maneja categorías genéricas; la API exige siete slots cerrados: `front_closed`, `left_side`, `right_side`, `back`, `top`, `front_open`, `serial_plate`.

### GPS

`LocationService` usa Geolocator, comprueba servicio/permisos, contempla denegación permanente y timeout; existen conversión de coordenadas y RTK. Debe persistir la muestra en el borrador y mapearla al esquema REST, sin hacer depender el guardado local de la red.

### Señal/conectividad

Existen `connectivity_plus`, diagnóstico celular, canal nativo/probe y reglas Wi-Fi. La API requiere `generation`, `connected`, `capturedAt` y admite datos opcionales. La captura debe degradarse a `UNKNOWN`/`NONE` cuando el dispositivo no exponga dBm u operador. La ausencia de `android/` elimina actualmente el canal nativo que sí existe en la app completa.

## 6. Servicios y componentes reutilizables

- Tema, widgets comunes, shell visual y componentes de formularios.
- `VisualInspectionRepository`, codec JSON versionado y modelos RV adaptables.
- Cola de sincronización, journal, cuarentena, auditoría y recuperación.
- Servicio confiable de fotografías, procesamiento, hash, miniaturas y reconciliación.
- `LocationService`, conversión de coordenadas y captura de conectividad/señal.
- Filtros/búsqueda de hidrantes y páginas de lista/detalle, sustituyendo la fuente mock.
- Pantalla de sincronización y etiquetas de estado, sustituyendo el transporte simulado.
- Pruebas existentes de persistencia, recuperación, medios, navegación y RV.

## 7. Componentes que deben sustituirse u ocultarse

- Sustituir login demo por registro/inicio de sesión de campo real.
- Sustituir `MockAssignmentSyncService`/demo data por API + caché local.
- Incorporar cliente Dio central, repositorios remotos y almacenamiento seguro.
- Sustituir checklist RV hardcodeado/modelo específico por definición dinámica, conservando adaptadores visuales donde sea útil.
- Implementar orquestador real de sincronización e idempotencia; la cola existente es infraestructura, no transporte API.
- Ocultar rutas, botones y contenido F02-B/RF mediante configuración de producto; no borrar destructivamente.
- Restaurar `android/` e `ios/` desde la app completa, manteniendo identidad y configuración de permisos; permitir HTTP solo en debug.
- Reducir la apertura de cajas y servicios funcionales en bootstrap cuando la bandera RV esté activa.

## 8. Contratos API confirmados

Base: `/api/v1`; autenticación de campo mediante Bearer JWT. `requestId` se devuelve en problemas RFC 7807 y el middleware acepta/establece el identificador de solicitud.

| Método y ruta | Contrato real relevante |
|---|---|
| `POST /field-sessions/start` | Body `name`, `email`, `phone`, `crew`, `device { installationId, platform, manufacturer, model, androidVersion, appVersion }`; 201 `sessionId`, `accessToken`, `refreshToken` y datos de rotación. |
| `GET /field-sessions/current` | Sesión abierta del token. |
| `POST /field-sessions/{id}/end` | Cierra sesión y revoca refresh; admite idempotencia global. |
| `POST /field-sessions/refresh` | Body `refreshToken`; rota el par de campo. |
| `GET /hydrants` | `search`, `municipality`, `locality`, `status`, `lat`, `lng`, `radiusKm`, `sort`, `page`, `pageSize`; devuelve `items`, paginación y campos reales SQL. |
| `GET /hydrants/{accountNumber}` | Consulta por cuenta normalizada. |
| `GET /checklists/rv/active` | Checklist por secciones/items, `version`, ETag e `If-None-Match`/304. |
| `POST /inspections` | Body `clientInspectionId`, `accountNumber`; idempotencia por UUID de cliente y opcional `Idempotency-Key`; 201 incluso al recuperar existente. |
| `GET /inspections/{id}` | Inspección y respuestas persistidas. |
| `PUT /inspections/{id}/answers` | Body `{ answers: [{ itemId, value?, notApplicable }] }`, 1..200. |
| `POST /inspections/{id}/location-samples` | Lat/lng obligatorios; altitud/precisiones/UTM opcionales; `source` y `capturedAt`. |
| `POST /inspections/{id}/signal-samples` | `generation`, `connected`, `capturedAt`; red/operador/dBm/nivel/roaming/datos técnicos opcionales. |
| `POST /inspections/{id}/photos` | `multipart/form-data`: `photo`, `photoId`, `slotCode`, SHA-256, `capturedAt`, metadata opcional; deduplicación por `photoId` + hash. |
| `GET /inspections/{id}/photos` | Lista de metadatos de fotos. |
| `GET /inspections/{id}/photos/{photoId}/content?size=` | Miniatura WebP u original JPEG. |
| `POST /inspections/{id}/submit` | Valida respuestas visibles obligatorias, GPS, señal y siete fotos verificadas; 422 con errores de dominio o 200 submitted. |
| `POST /inspections/{id}/cancel` | Cancela borrador editable con `reason`. |

Tipos de checklist reales: `boolean`, `text`, `integer`, `decimal`, `select`, `multiselect`, `photo`, `coordinates`, `signal`, `readonly`, `date`. Dependencias: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`. No existe un tipo separado `observación` ni una opción genérica `no aplica`; `notApplicable` pertenece a la respuesta.

La API no expone catálogo de cuadrillas para el usuario de campo. `crew` es texto normalizado y `start` crea la cuadrilla si no existe. Esto contradice la expectativa de seleccionar un catálogo existente, aunque no impide el flujo técnico.

## 9. Diferencias entre OpenAPI y código

`docs/openapi.yaml` sirve como índice, pero está incompleto frente al código ejecutable:

- Omite `POST /field-sessions/refresh`.
- Omite `GET /hydrants/{accountNumber}` y filtros reales de municipio, localidad, estado, distancia y orden.
- Omite bodies/esquemas detallados de creación, respuestas, GPS, señal y submit.
- Omite `POST /inspections/{id}/cancel`.
- Omite `GET /inspections/{id}/photos/{photoId}/content`.
- Documenta refresh/logout solo para admin; el campo rota refresh por otra ruta y termina sesión mediante `/end`.
- No documenta respuestas concretas ni el shape completo del checklist/hidrante/tokens.
- Declara `Idempotency-Key` solo en algunas operaciones, pero el middleware lo procesa globalmente en POST/PUT/PATCH/DELETE. Atención: como `express.json()` corre antes que Multer, el hash idempotente de multipart no incluye archivo/campos multipart; para fotos debe prevalecer `photoId` + SHA-256.
- OpenAPI marca `device` solo como objeto, mientras Zod exige sus seis propiedades.

Se propone consumir conforme al código/Zod y registrar esta deuda, sin modificar la API en esta etapa.

## 10. Validación ejecutada

- `flutter pub get`: correcto; 13 paquetes tienen versiones nuevas incompatibles con las restricciones actuales (no es bloqueo).
- `flutter analyze`: exit 0, `No issues found` (13.0 s).
- `flutter test`: exit 0, **85 pruebas aprobadas** (15 s), ninguna falla.
- El primer intento dentro del sandbox agotó tiempo por acceso a la caché externa del SDK; la ejecución autorizada fuera del sandbox concluyó correctamente.

## 11. Pruebas existentes y huecos

Hay cobertura unitaria/widget sobre reglas RV, secuencia/componentes, persistencia, serialización, colas, recuperación, medios, filtros, estado de reportes y señal. Existe `integration_test/offline_startup_test.dart` pero `flutter test` no ejecuta automáticamente integración sobre dispositivo.

Faltan pruebas del cliente REST, refresh concurrente, sesión segura, ETag/304, parsing de problemas, hidrantes paginados, mapeo checklist dinámico, idempotencia, sincronización completa, multipart, reapertura offline y submit end-to-end.

## 12. Deuda técnica y riesgos

1. **Bloqueante de publicación/build:** ausencia total de `android/` e `ios/` en la app RV.
2. **Identidad/firma:** debe restaurarse exactamente desde la app completa y usarse la misma firma externa; no se puede certificar desde RV hoy.
3. **Contrato de cuadrilla:** no hay endpoint de catálogo de campo; la API crea cuadrillas desde texto libre.
4. **Modelo divergente:** UI RV actual es específica y hardcodeada; la API es checklist dinámico versionado.
5. **Código fuera de alcance visible:** F02-B/RF sigue en rutas, bootstrap y navegación.
6. **Seguridad:** tokens aún no tienen almacenamiento seguro; sesión demo usa preferencias.
7. **Sincronización:** colas maduras pero transporte real inexistente; se debe preservar orden create → answers/GPS/signal/photos → submit.
8. **Propiedad:** `GET /inspections/{id}` no filtra explícitamente por `user_id`, a diferencia de escrituras y fotos; debe reportarse a la API antes de una eventual corrección.
9. **Submit:** exige siete slots fijos además del checklist dinámico; la UI debe hacerlo explícito.
10. **OpenAPI incompleto:** generar clientes solo desde ese archivo produciría un cliente insuficiente.
11. **Idempotencia multipart:** no confiar en `Idempotency-Key` para contenido de foto; usar identidad/hash propios.
12. **Compatibilidad Android local HTTP:** aún no hay manifests donde aplicar una excepción solo debug.

