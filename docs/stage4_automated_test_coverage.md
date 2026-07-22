# Cobertura automatizada previa a DDR001 API

Fecha de preparación: 2026-07-15. Estado de ejecución: **pendiente de ejecución manual**. Esta matriz describe pruebas creadas; no afirma que pasaron hasta ejecutar los comandos de `docs/testing.md`.

## Prioridades adoptadas

Las fuentes de Etapa 4 no contenían etiquetas P0/P1/P2 explícitas. Etapa 4D adopta y documenta esta proyección:

- P0: pérdida/integridad de datos, estados, inmutabilidad, recuperación, sincronización local y aislamiento de la prueba celular.
- P1: reglas funcionales offline, serialización, cálculos, filtros, widgets y navegación.
- P2: hardware, implementación Android real, rendimiento y accesibilidad que requieren dispositivo.

## Matriz

| Regla | Prioridad | Nivel automatizado | Archivo | Estado |
|---|---:|---|---|---|
| Transiciones RV/RF permitidas y prohibidas | P0 | Dominio real | `test/domain/report_state_machine_test.dart` | Creada, no ejecutada |
| Motivo obligatorio al suspender/cancelar/repetir | P0 | Dominio real | `test/domain/report_state_machine_test.dart` | Creada, no ejecutada |
| Revisión lineal vigente | P0 | Dominio real | `test/domain/report_revision_resolver_test.dart` | Creada, no ejecutada |
| Bifurcación, ciclo y referencia ausente | P0 | Dominio real | `test/domain/report_revision_resolver_test.dart` | Creada, no ejecutada |
| JSON versionado y lectura heredada | P0 | Serialización real | `test/serialization/versioned_models_test.dart` | Creada, no ejecutada |
| UUID/relaciones de válvulas, corridas y alarmas | P1 | Serialización real | `test/serialization/functional_collection_models_test.dart` | Creada, no ejecutada |
| Marca/modelo libre heredado y snapshot inmutable | P1 | Serialización real | `test/serialization/functional_collection_models_test.dart` | Creada, no ejecutada |
| Journal round-trip, fase y UTC | P0 | Serialización/Hive real | `test/serialization`, `test/repositories` | Creada, no ejecutada |
| Prepared vacío sin datos inventados | P0 | Hive/recuperación real | `test/recovery/recovery_coordinator_test.dart` | Creada, no ejecutada |
| Índice inequívoco recreado | P0 | Hive/recuperación real | `test/recovery/recovery_coordinator_test.dart` | Creada, no ejecutada |
| Operación ambigua queda needsRecovery | P0 | Hive/recuperación real | `test/recovery/recovery_coordinator_test.dart` | Creada, no ejecutada |
| Índice huérfano detectado y retirado | P0 | Hive/auditor real | `test/recovery/recovery_coordinator_test.dart` | Creada, no ejecutada |
| Cuarentena conserva original y hash | P0 | Hive real | `test/repositories/local_repositories_test.dart` | Creada, no ejecutada |
| Dependencias e ilegibles en cola local | P0 | Hive real | `test/repositories/local_repositories_test.dart` | Creada, no ejecutada |
| Foto sin cola se reencola pendingUpload | P0 | Hive/filesystem real | `test/media/media_reconciliation_test.dart` | Creada, no ejecutada |
| uploadedUnverified no equivale a verified | P0 | Hive/filesystem real | `test/media/media_reconciliation_test.dart` | Creada, no ejecutada |
| Faltante/eliminación lógica no borra documento | P0 | Hive/filesystem real | `test/media/media_reconciliation_test.dart` | Creada, no ejecutada |
| Contrato MethodChannel celular y payload privado | P0 | Binary messenger real con handler controlado | `test/platform/cellular_internet_probe_channel_test.dart` | Creada, no ejecutada |
| Error/restricción celular queda indeterminado | P0 | Adaptador real | `test/platform/cellular_internet_probe_channel_test.dart` | Creada, no ejecutada |
| Cancelación envía probeId | P0 | Adaptador real | `test/platform/cellular_internet_probe_channel_test.dart` | Creada, no ejecutada |
| Controlador persiste progreso/éxito/cancelación sin timer duplicado | P0 | Controlador real + fake de borde nativo | `test/platform/cellular_network_diagnostics_controller_test.dart` | Creada, no ejecutada |
| HTTP realmente ligado a `Network` celular | P2 | Android físico | Matriz manual GPRS/4C | Preparada, no certificada |
| Conversiones y fórmulas conocidas | P1 | Dominio real | `test/domain/typed_measurement_calculator_test.dart` | Creada, no ejecutada |
| Patrón cero/operación no calculable | P1 | Dominio real | `test/domain/typed_measurement_calculator_test.dart` | Creada, no ejecutada |
| Wi-Fi condicional, normalización y validación | P1 | Dominio real | `test/domain/wifi_assessment_rules_test.dart` | Creada, no ejecutada |
| Seis filtros y agregación RV/RF | P1 | Dominio real | `test/domain/hydrant_query_projection_test.dart` | Creada, no ejecutada |
| Request Inicio→Hidrantes, consumo y conteos compartidos | P1 | AppState + Hive real | `test/navigation/home_hydrant_filter_request_test.dart` | Creada, no ejecutada |
| Contador filtra fotos inválidas/eliminadas | P1 | Widget + filesystem | `test/widgets/section_photo_counter_test.dart` | Creada, no ejecutada |
| Duplicar válvula no copia pruebas/evidencia | P1 | Widget/producción real | `test/widgets/valve_editor_test.dart` | Creada, no ejecutada |
| Arranque offline básico | P1/P2 | `integration_test` | `integration_test/offline_startup_test.dart` | Creada, requiere runner/dispositivo |
| Navegación shell completa, Atrás y predictive back | P1/P2 | Integración/dispositivo | Matriz manual M03/RF-01 | Pendiente de ampliar tras harness de sesión estable |
| Cámara, GPS, cierre forzado, 1000 fotos, TalkBack | P2 | Dispositivo | `docs/stage4_manual_test_matrix.md` | No certificado |

## Discrepancias detectadas

- La documentación describe una autoridad única de sincronización; bootstrap conserva `sync_queue`, `media_sync_queue` y `media_work_queue_v1`. Las pruebas validan su reconciliación actual y no afirman una transacción única entre cajas.
- `QuarantineRepository` recibe la caja por inyección; bootstrap usa `quarantine_documents_v1`. Los tests usan una caja temporal aislada y verifican el contrato, no el nombre productivo.
- El escaneo real de transporte celular no puede probarse desde un host Dart. El test automatizado verifica el MethodChannel y la clasificación; `Network.openConnection` y liberación de `NetworkCallback` siguen siendo P2 Android.
- No existía cobertura previa ni porcentaje base. El porcentaje solo será válido después de `flutter test --coverage`; contar archivos no es cobertura.

## Cobertura pendiente prioritaria

- Harness visual completo de StatefulShellRoute, alertas, Atrás y auto-scroll; el ciclo de request y conteos de `AppState` sí tiene prueba automatizada.
- Flujo widget integral RV/RF con cámara/ubicación sustituidas por fakes inyectables.
- WorkCreationCoordinator RV+RF con fixtures completos de `Hydrant`, `AppUser` e inspecciones.
- Repositorios funcionales con finalización/revisión y colecciones múltiples desde Hive.
- ThumbnailRegenerationService con codec de imagen controlable; la compresión nativa no se certifica en test host.
