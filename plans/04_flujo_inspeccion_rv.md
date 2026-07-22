# Flujo completo de inspección RV

Fecha: 2026-07-22. Rama: `feature/rv-inspection-flow`. Solo se escribió en `ddr001_diag_rv_app`; las apps de referencia y la API se consultaron en modo lectura.

## Contratos reales

La fuente fue el código TypeScript, no solo OpenAPI.

| Operación | Contrato |
|---|---|
| Crear | `POST /inspections`, `clientInspectionId`, `accountNumber`, `Idempotency-Key` |
| Consultar | `GET /inspections/{id}` |
| Respuestas | `PUT /inspections/{id}/answers`, lote `{answers:[{itemId,value?,notApplicable}]}` |
| GPS | `POST /inspections/{id}/location-samples` |
| Señal | `POST /inspections/{id}/signal-samples` |
| Foto | `POST /inspections/{id}/photos`, multipart `photo`, `photoId`, `slotCode`, `clientSha256`, `capturedAt`, `metadata` |
| Fotos | `GET /inspections/{id}/photos` y `GET /inspections/{id}/photos/{photoId}/content` |
| Enviar | `POST /inspections/{id}/submit` |
| Cancelar | `POST /inspections/{id}/cancel`, motivo de 3 a 500 caracteres |

La API permite editar `draft`, `in_progress`, `pending_sync` y `rejected`. Submit requiere respuestas visibles, ubicación, señal y siete fotos verificadas.

## Modelo, persistencia y estados

`RvDraft` conserva UUID cliente estable, ID servidor, hidrante/cuenta/sesión, ID/versión/snapshot del checklist, respuestas, GPS, señal, fotos y estado/reintentos por etapa. Se serializa dentro de `VisualInspection.unknownFields['rvDynamicDraft']`; reutiliza `visual_inspections_v1`, índice activo, codec versionado y recuperación existentes, sin una segunda fuente local.

Estados: `draft`, `pendingCreate`, `creating`, `created`, `pendingAnswers`, `pendingLocation`, `pendingSignal`, `pendingPhotos`, `readyToSubmit`, `submitPending`, `submitting`, `submitted`, `syncError`, `cancelled`. Las partes usan `notCaptured`, `pending`, `syncing`, `synced`, `error`. Se guardan paso, intento, error y siguiente reintento.

## Renderer y validación

El formulario usa el snapshot dinámico, no el checklist heredado. Renderiza tipos reales `boolean`, `select`, `multiselect`, `text`, `integer`, `decimal`, `date`; `photo`, `coordinates`, `signal`, `readonly` usan UI de evidencia. Respeta secciones, orden, opciones, ayuda, obligatoriedad y dependencias `eq`, `neq`, `in`, `gt`, `gte`, `lt`, `lte`.

Las respuestas ocultas se conservan localmente y se sincronizan como `notApplicable: true`, igual que la normalización de `answers.service.ts`. Submit valida tipos, opciones, visibles obligatorias, GPS, señal, slots y sincronización.

## GPS, señal y fotografías

GPS reutiliza `LocationService` y persiste coordenadas, altitud, precisiones, fuente y fecha antes de REST. Maneja permiso, denegación permanente, servicio apagado y timeout.

Señal usa `connectivity_plus`; envía conectividad/tipo disponibles y no inventa dBm, nivel, operador o roaming. Android e iOS no garantizan intensidad celular mediante esta capa portable.

Fotos reutilizan `ReliablePhotoService`, `InspectionPhoto`, `inspection_photos_v1`, journal y reconciliación: orientación, compresión, miniatura, SHA-256, dimensiones y metadatos se guardan antes de asociar el UUID al slot. Los archivos no se eliminan al subir.

Slots confirmados en `photo.routes.ts` y `submit.service.ts`: `front_closed`, `left_side`, `right_side`, `back`, `top`, `front_open`, `serial_plate`. Deduplicación por `photoId` + `clientSha256`; reconciliación por UUID, slot y estado/hash.

## Sincronización y recuperación

Orden reanudable: crear, respuestas agrupadas, GPS, señal, fotos secuenciales, reconciliar, validar, submit, confirmar. Nunca envía dependencias sin ID servidor. Repite creación con el mismo `clientInspectionId`; el backend devuelve la existente. Tras timeout de submit consulta el estado remoto.

Reintentos temporales: 5, 15 y 45 segundos, sin bucles. Offline, timeout y servidor no disponible son reintentables; validación/autorización no. El arranque recupera Hive y la sincronización global procesa pendientes secuencialmente. Submitted/cancelled son solo lectura.

## Incompatibilidad real encontrada

`processPhoto` del backend vuelve a codificar con Sharp y compara el SHA-256 resultante con `clientSha256`. Flutter normaliza con `flutter_image_compress`; codificadores distintos pueden producir bytes distintos para la misma imagen y causar `422 Hash mismatch`. No se modificó la API. Corrección mínima propuesta para una etapa autorizada: usar el hash cliente para identidad del archivo recibido y guardar aparte el hash normalizado servidor, sin exigir igualdad byte a byte entre codificadores.

## Archivos y pruebas

Nuevos: dominio `rv_draft.dart`, `rv_sync_state.dart`, `rv_validator.dart`; datos `rv_draft_repository.dart`, `inspection_remote_repository.dart`, `inspection_capture_services.dart`, `inspection_sync_coordinator.dart`; UI `dynamic_checklist_renderer.dart`, `rv_inspection_controller.dart`, `rv_inspection_page.dart`, `rv_summary_page.dart`; pruebas `test/inspections/rv_inspection_domain_test.dart`.

Modificados: bootstrap, router, AppState, repositorio/modelo visual, prueba de AppState y planes. Los resultados finales de analyze, test y APK se registran en el informe de cierre.

## Comandos

```powershell
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
flutter test
flutter analyze
flutter build apk --debug --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
```

## Pendientes

- Resolver el contrato de hash y realizar E2E con siete fotos.
- Prueba manual en dispositivo físico con sesión real y verificación dashboard/SQL.
- Telemetría sin datos sensibles y política de retención de medios.
- Evaluar sincronización background solo tras estabilizar foreground.
