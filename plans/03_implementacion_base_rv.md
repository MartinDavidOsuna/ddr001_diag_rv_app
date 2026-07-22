# Implementación de la base funcional RV

Fecha: 2026-07-22  
Rama: `feature/rv-foundation`

## 1. Resultado

Se restauraron Android/iOS y se implementó la base técnica para sesión de campo real, caché de hidrantes, checklist dinámico y producto exclusivamente RV. No se modificaron `DDR001_DIAG`, `DDR001_API_RV`, Swagger, Helmet, SQL Server ni contratos. No se generó llave de firma.

## 2. Plataformas restauradas

Se copiaron los 61 archivos nativos rastreados por Git de `C:\DEV\AQAGS\ddr001_diag\android` y `ios` usando `git ls-files`. Se excluyeron explícitamente:

- `android/local.properties` de la referencia;
- cualquier `key.properties`;
- `*.jks` y `*.keystore`;
- `ios/Flutter/ephemeral` y archivos `.env` efímeros.

Android restaurado incluye scripts Gradle Kotlin, wrapper, manifests main/debug/profile, Kotlin `MainActivity` y canal celular, recursos, iconos y splash. iOS restaurado incluye proyecto/workspace, configuraciones Flutter, Runner, permisos, storyboards, iconos y pruebas.

`flutter build` generó un `android/local.properties` local e ignorado por Git; no forma parte de los cambios versionables.

## 3. Identidad verificada

- Android Gradle Kotlin DSL.
- `namespace = "com.aquafim.ddr001diag"`.
- `applicationId = "com.aquafim.ddr001diag"`.
- Android `app_name = DIAGNOSTICO HIDRANTES` y manifest usa `@string/app_name`.
- iOS `PRODUCT_BUNDLE_IDENTIFIER = com.aquafim.ddr001diag` para Debug/Profile/Release.
- iOS `CFBundleDisplayName` y `CFBundleName`: `DIAGNOSTICO HIDRANTES`.
- Dart package `ddr001diag`, versión `0.2.0+3`.

Se conservaron permisos de cámara, ubicación fina/aproximada, Internet y estado de red; iOS conserva textos de cámara, galería y ubicación.

## 4. Firma

La app completa no contiene configuración productiva ni referencias a `key.properties`. `android/app/build.gradle.kts` configura actualmente el build `release` con `signingConfigs.getByName("debug")`. No se copió ni creó ninguna llave.

Por seguridad no se generó AAB release: aunque Gradle podría producir uno con firma debug, no sería válido para actualizar la aplicación publicada. Para certificar release se requiere la configuración/keystore productiva existente fuera de Git, sin incorporarla al repositorio.

## 5. Configuración de entorno y HTTP local

`AppConfig` lee `APP_ENV` y `API_BASE_URL` con `String.fromEnvironment`, expone `isDevelopment` y `rvOnly`, valida URL y exige HTTPS en release. Solo development debug usa temporalmente `http://192.168.1.111:3000/api/v1` si falta el define.

El manifest principal no habilita cleartext. `android/app/src/debug/AndroidManifest.xml` agrega `usesCleartextTraffic=true`; release conserva la política segura. `INTERNET` existe en main.

## 6. Cliente HTTP

`ApiClient` centraliza Dio con:

- base URL única;
- timeouts de conexión 15 s y envío/recepción 25 s;
- `Accept: application/json`;
- Bearer automático;
- `X-Request-ID` UUID;
- cabeceras libres para ETag e idempotencia;
- errores españoles tipados: offline, timeout, sesión expirada, datos inválidos, servidor, validación y desconocido;
- logs debug limitados a método/ruta/status, sin headers, bodies ni tokens;
- retry único tras 401;
- refresh rotativo compartido para evitar refresh concurrentes.

## 7. Sesión segura

`SessionSecureStorage` usa `flutter_secure_storage` para access token, refresh token, session ID e installation ID. El UUID se crea una vez y sobrevive al cierre de sesión. Los datos de perfil de campo se conservan junto a la sesión segura para restauración offline.

El formulario demo se sustituyó por nombre, correo, teléfono y cuadrilla libre. Normaliza espacios, correo minúsculo y cuadrilla mayúscula; valida nombre, formato de correo y teléfono de diez dígitos. Envía exactamente:

```text
name, email, phone, crew,
device.installationId, platform, manufacturer, model, androidVersion, appVersion
```

Al arrancar, la app lee sesión segura y consulta `/field-sessions/current`. Un 401 dispara una rotación y un único retry. Si la red no está disponible conserva la sesión y muestra `Sesión sin verificar — modo sin conexión`. El cierre usa `/field-sessions/{id}/end`; si está offline conserva tokens/datos, marca `pending_field_session_end` y no pierde borradores.

## 8. Hidrantes y caché

`HydrantRepository` implementa:

- `GET /hydrants` con paginación real de hasta 200;
- búsqueda remota preparada mediante `search`;
- `GET /hydrants/{accountNumber}`;
- DTO desacoplado y mapper al `Hydrant` heredado;
- almacenamiento JSON en Hive `local_hydrants_v1`;
- lectura cache-first y fecha de última actualización;
- upsert sin borrar hidrantes ausentes de una página parcial;
- conservación de caché ante error.

La UI muestra inmediatamente Hive y el botón de refresco sustituye la simulación de asignaciones por la API real.

## 9. Checklist dinámico

`ChecklistRepository` y modelos locales conservan ID, código, versión, título, publicación, secciones, items, tipos, orden, obligatoriedad, unidad, opciones, dependencia, slot fotográfico y ayuda.

Flujo:

1. Lee `rv_checklist_cache_v1`.
2. Envía `If-None-Match` con el ETag local.
3. En 200 persiste definición y ETag.
4. En 304 reutiliza el documento local.
5. En error de red reutiliza caché.
6. Sin caché propaga error recuperable en español.

`DynamicChecklistAdapter` deja listos los items respondibles. La UI hardcodeada existente continúa temporalmente para no ampliar esta etapa, pero el checklist remoto es ya la fuente canónica descargada; el renderer final se implementará con inspecciones.

## 10. Producto RV-only

`AppConfig.rvOnly = true`. La ruta `/hydrants/:id/inspection/b` redirige al detalle y el renderer fuerza tipo `a`. Se ocultan nuevo levantamiento genérico, tarjeta funcional, repetición RF e historial RF. Los archivos F02-B/RF permanecen sin borrarse. El manual dejó de mostrar terminología RF. La prueba `configuración RV bloquea F02-B y conserva RV` certifica el guard.

## 11. Dependencia agregada

```yaml
flutter_secure_storage: ^10.0.0
```

Resuelta como `10.3.1`. Dio, UUID, connectivity_plus, Hive, device_info y package_info ya existían.

## 12. Pruebas

Se agregaron 16 casos a la base de 85, total 101:

- configuración explícita y rechazo release inseguro;
- correo/teléfono y normalización de nombre/cuadrilla;
- installation ID persistente y almacenamiento/restauración de sesión;
- request real de inicio de campo y datos de dispositivo;
- restauración offline;
- refresh rotativo y exclusión concurrente;
- traducción de 401/sin conexión;
- guard RV-only;
- mapper y caché no destructivo de hidrantes;
- checklist 200, ETag 304 y fallback offline.

No usan API real. `flutter analyze`: sin issues. `flutter test`: 101/101 aprobadas.

## 13. Red y compilación

API local verificada desde el equipo:

```json
GET /health/live  -> {"status":"ok"}
GET /health/ready -> {"status":"ready","database":"ok","storage":"ok","configuration":"ok"}
```

APK generado:

```text
C:\DEV\AQAGS\ddr001_diag_rv_app\build\app\outputs\flutter-apk\app-debug.apk
```

Tamaño: 163,185,506 bytes. Gradle emitió advertencias no bloqueantes sobre migración futura Built-in Kotlin de `flutter_image_compress_common`, Java source/target 8 y API deprecated del plugin.

No había un dispositivo/emulador y datos reales de un inspector autorizados para crear una sesión persistente en SQL Server; la prueba manual dentro de Flutter queda para instalación en equipo Android. El contrato completo está cubierto con fake y la API saludable.

## 14. Ejecución local

```powershell
flutter pub get
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
```

Build reproducible:

```powershell
flutter build apk --debug --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
```

Release futuro debe recibir URL HTTPS:

```powershell
flutter build appbundle --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.ejemplo.mx/api/v1
```

Este último comando solo debe ejecutarse después de disponer de la firma productiva existente.

## 15. Pendientes y riesgos

- Conectar el checklist dinámico al renderer de captura y persistir respuestas versionadas.
- Implementar creación idempotente de inspección y orquestador de sync real.
- Integrar GPS, señal, siete slots fotográficos y submit.
- Probar sesión/caché en un dispositivo físico contra la LAN.
- Incorporar de forma segura la firma productiva existente fuera de Git.
- Actualizar en una fase separada el plugin de compresión para Built-in Kotlin.
- La API mantiene las deudas documentadas de OpenAPI y lectura de inspección sin filtro explícito de propietario.

## 16. Archivos exactos previstos para inspecciones (siguiente etapa)

### Nuevos

- `lib/features/inspections/data/inspection_api_models.dart`
- `lib/features/inspections/data/inspection_remote_repository.dart`
- `lib/features/inspections/data/inspection_sync_coordinator.dart`
- `lib/features/inspections/domain/rv_draft.dart`
- `lib/features/inspections/domain/rv_sync_state.dart`
- `lib/features/checklist/presentation/dynamic_checklist_renderer.dart`
- `lib/features/checklist/presentation/checklist_field_factory.dart`
- `lib/features/inspections/presentation/rv_summary_page.dart`
- `test/inspections/inspection_remote_repository_test.dart`
- `test/inspections/inspection_sync_coordinator_test.dart`
- `test/inspections/rv_draft_persistence_test.dart`
- `test/checklist/dynamic_checklist_renderer_test.dart`

### Modificados

- `lib/app/bootstrap.dart`
- `lib/app/router/app_router.dart`
- `lib/core/services/app_state.dart`
- `lib/data/local/visual_inspection_repository.dart`
- `lib/domain/inspections/visual_inspection.dart`
- `lib/domain/inspections/visual_inspection_step_validator.dart`
- `lib/domain/sync/sync_queue_item.dart`
- `lib/data/local/sync_queue_repository.dart`
- `lib/features/visual_report/presentation/visual_report_page.dart`
- `lib/features/hydrants/hydrant_pages.dart`
- `lib/features/sync/sync_page.dart`
- `test/repositories/local_repositories_test.dart`
- `test/serialization/versioned_models_test.dart`

Los módulos GPS, señal y fotos existentes se conectarán en la etapa posterior de evidencia, sin reescribirlos.

## Actualización de la etapa 3 (2026-07-22)

La base fue extendida en `feature/rv-inspection-flow`: el checklist cacheado se captura como snapshot inmutable por borrador, el repositorio visual existente sigue siendo la fuente local única y la ruta RV usa el renderer dinámico, resumen y coordinador REST reales. Los contratos, estados, pruebas y el riesgo detectado en el hash de fotografías se documentan en `plans/04_flujo_inspeccion_rv.md`.
