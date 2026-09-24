# Cierre Ausente porque no hay hidrante en la ubicación

## Decisión de dominio

`inactive` es un estado local terminal y de solo lectura de una revisión RV. No
es el estado global del hidrante maestro. El resultado asociado se persiste como
`RvInactiveClosure` con el motivo canónico
`NO_HYDRANT_AT_CAPTURED_LOCATION`.

El cierre conserva una copia inmutable de:

- coordenada y precisión capturadas;
- fecha de captura y fecha de cierre;
- comentario de 10 a 500 caracteres;
- uno o más `photoId` del slot exclusivo `no_hydrant_at_location`;
- usuario, cuadrilla y dispositivo;
- clave de idempotencia derivada de la identidad completa del cierre;
- versión de contrato y estado de sincronización.

El estado inicial de sincronización es `pendingApiContract`. Mientras el
servidor no implemente el contrato, la revisión permanece visible como
“Ausente · pendiente de sincronizar”, no se envía por el flujo normal y no
se marca como confirmada remotamente.

Los documentos legacy no contienen `inactiveClosure`; el campo es opcional y su
ausencia conserva exactamente la semántica anterior. No hay reescritura ni
migración masiva de cajas Hive.

## Persistencia local

Antes del cierre existe un estado opcional y aditivo
`RvInactiveClosureDraft`. Conserva el identificador único del borrador, una
copia exacta de la coordenada persistida en el paso 1, comentario parcial,
`photoId`, usuario, cuadrilla, dispositivo y estado de recuperación. No cambia
el estado local a `inactive`, no completa el contenedor y no retira el índice
activo.

Al salir con contenido guardado, la interfaz obliga a elegir entre:

- **Guardar para continuar después**: conserva el borrador activo y excluye su
  slot fotográfico del pipeline normal.
- **Descartar este reporte**: valida que cada foto sea local, exclusiva de la
  revisión, usuario, dispositivo y slot dedicado, sin estado remoto ni cierre
  confirmado. Una operación journaled retira sólo esas referencias, marca los
  documentos de foto con `deletedAt` y resuelve sus dos colas como
  `discardedLocalInactiveDraft`. Los archivos físicos se conservan para
  recuperación y auditoría; no se produce un huérfano accionable.

Un descarte interrumpido converge durante recovery utilizando la identidad
exacta registrada en el journal. Si no puede demostrarse exclusividad, no
modifica la evidencia y exige revisión manual.

Justo antes de abrir la cámara se persiste un borrador vacío de recuperación.
Así, Android puede restaurar la intención y `retrieveLostData` tras process
death. Si la cámara vuelve cancelada y el reporte no tenía contenido previo,
ese placeholder se descarta de forma journaled y no queda evidencia ni bloqueo.

El cierre local es una operación journaled e idempotente:

1. valida propiedad, dispositivo, edición y coordenada persistida;
2. valida comentario y al menos una referencia del slot exclusivo;
3. comprueba documento, archivo, tamaño y SHA-256 físico de cada foto;
4. persiste el sobre `inactiveClosure` dentro del documento RV existente;
5. marca el documento contenedor como terminado sólo para volverlo inmutable;
6. retira y confirma la ausencia de la revisión en el índice activo;
7. conserva documento, fotografías, colas y journal para auditoría.

Las capturas nuevas guardan de forma aditiva `receivedSha256`, calculado en
streaming sobre los bytes entregados por la cámara antes de normalizar, además
del `sha256` ya existente del JPEG normalizado. Las fotografías legacy siguen
siendo legibles cuando el campo no existe. El cierre Ausente exige ambos
hashes porque sólo puede usar evidencia creada por esta versión o una posterior.

Cancelar antes de tomar una fotografía y sin comentario no produce cambios. Si
la cámara ya entregó evidencia o existe comentario útil, no se permite salir
sin guardar o descartar explícitamente. La revisión permanece editable y el
cierre no ocurre hasta confirmar todos los requisitos.

La repetición del cierre compara `clientInspectionId`, motivo, comentario,
coordenada y timestamp, usuario, dispositivo, IDs y ambos hashes de cada foto,
versión de contrato y clave de idempotencia. Una identidad distinta se rechaza
sin sobrescribir el cierre confirmado.

La UI y las proyecciones usan `RvDraft.localStatus == inactive`, por lo que el
documento no se presenta como una revisión enviada/finalizada normal. El estado
del contenedor no autoriza cambiar `rv.hydrants.is_active` ni
`rv.hydrant_rv_status`.

## Contrato API verificado (2026-09-24)

Fuentes leídas en `MartinDavidOsuna/ddr001_api`, `main`, commit
`ea73ad4e33394d43830a3f731c34c1f8050be416`:

- [Contrato](https://github.com/MartinDavidOsuna/ddr001_api/blob/ea73ad4e33394d43830a3f731c34c1f8050be416/docs/rv-inactive-closure.md)
- [OpenAPI](https://github.com/MartinDavidOsuna/ddr001_api/blob/ea73ad4e33394d43830a3f731c34c1f8050be416/docs/openapi.yaml)
- `src/modules/inspections/inactive.schema.ts` y `inactive.service.ts`.

La ruta Windows suministrada no existe en este equipo macOS. Se leyó su contrato
publicado en remoto; no se utilizó como autoridad la copia local antigua de la API.
No se comprobó despliegue ni se modificó producción.

## Sincronización exclusiva

La cola se reconstruye desde los documentos originales del usuario actual mediante
`pendingInactiveClosures()`, incluyendo `pendingApiContract` históricos. Restaurar
la sesión y recuperar conectividad ejecuta el coordinador unificado. Un observador
de documentos activa los cierres nuevos y un temporizador respeta el próximo
reintento de fallos transitorios; se detiene para conflictos/errores de contrato,
sin sesión o al destruir AppState. Los cierres
Ausente se procesan por una ruta independiente, sin checklist, respuestas, válvulas,
señal, `/submit`, cambios al hidrante maestro o creación de otra revisión.

1. Exigir usuario propietario en el scope actual, también después de cada llamada
   remota. Un bloqueo compartido por UUID impide coordinadores concurrentes.
2. Consultar `/version` y exigir el booleano `features.rvInactiveClosure == true`.
   Ausencia de soporte mantiene `pendingApiContract`, mensaje y espera de reintento.
3. Consultar por el mismo `clientInspectionId`; conservar el enlace remoto o crear
   con ese UUID. Un recibo ya coincidente resuelve la respuesta perdida sin subir fotos.
4. Consultar fotos del documento, verificar las existentes, subir las pendientes
   con sus UUID, fecha y slot originales, y verificar recepción con `verify-batch`.
5. Enviar exclusivamente `contractVersion`, `idempotencyKey`, `reasonCode`, `comment`,
   `closedAt`, `location`, `photoIds` a `POST /inspections/{id}/inactive`.
6. Validar recibo 200/201: UUID remoto, `inactive`, etiqueta, fecha de recepción,
   clave, motivo, comentario, ubicación, fechas y conjunto de fotos. Persistir el
   recibo completo y hacer `flush()` antes de marcar `remoteVerified`. Una escritura
   final interrumpida puede completarse usando ese recibo guardado.

Los nuevos estados de sincronización son aditivos; no se renombran valores antiguos.
El estado final de revisión permanece `inactive` durante todos los reintentos.
`remoteReceipt` también conserva el recibo discrepante para resolución explícita.
Ninguna ruta borra originales o fotografías para resolver errores.

## Errores y presentación

- 401 y fallos transitorios: pendiente con espera creciente; conservar documentos y
  reanudar con sesión válida del mismo propietario.
- 404/422 y contrato local incompatible: `requiresReview` y mensaje visible. Sin bucle
  automático permanente; reintento explícito desde el resumen tras revisar el problema.
- 409: consultar de nuevo el recibo. Sólo coincidencia real confirma; de otro modo
  `conflict`, conservando los dos contenidos. Nunca sobrescribir ni convertir en submit.
- Falta de evidencia (`INACTIVE_EVIDENCE_REQUIRED/INVALID`) no se clasifica como conflicto
  de identidad. Slot/UUID incompatible sí exige resolver identidad.

Listas, resumen, accesibilidad y exportaciones muestran **Ausente · pendiente de
sincronizar** o **Ausente · sincronizada**. El mapa ofrece un filtro de Ausente basado
en revisiones y conserva separado el filtro administrativo **Hidrante inactivo**.
Los seis grupos de checklist/envío normal excluyen este cierre; sigue visible en
Todas mis revisiones y la cola global de sincronización mientras esté pendiente.

## Diferencias detectadas respecto del modelo local anterior

- API: 1–20 fotos, UUID válidos; el modelo anterior sólo exigía una o más fotos.
  Se limita la captura/cierre nuevo a 20. Cierres históricos incompatibles se conservan
  íntegros para revisión; no se truncan listas ni se regeneran UUID o claves.
- Fuentes aceptadas: `gps`, `network`, `manual`, `rtk`. Valores históricos distintos
  permanecen guardados y se informan como incompatibilidad de contrato.
- Precisión vertical no negativa y clave de 16–120 caracteres. Validación antes del
  comando; no se reparan originales silenciosamente.
- La API normaliza fechas a milisegundos. La comparación usa esa precisión manteniendo
  los timestamps locales originales, evitando un conflicto falso por microsegundos.
- La ubicación permite UTM opcional; la app actual no lo guarda en `RvLocationSample`,
  por lo que no inventa ni envía esos campos.

## Verificación

`test/inspections/rv_inactive_sync_test.dart` cubre contrato HTTP real con transporte
simulado, cierre histórico, persistencia Hive/reapertura, respuesta perdida, evidencia
pendiente/reutilizada, conflictos, sesiones, aislamiento, concurrencia, API sin soporte,
normalización temporal y protección frente al flujo ordinario. Se conservan las pruebas
existentes de captura offline, hashes, descarte seguro y recuperación de cámara.

Ejecutar `flutter analyze --no-pub` y `flutter test --no-pub`. Estas pruebas son locales;
no sustituyen una aceptación física ni una prueba con la API desplegada.

### Revisión adicional contra la API local actualizada

La copia local de `ddr001_api/main` quedó en el mismo commit de las fuentes citadas.
Se revisaron además el endpoint multipart y la verificación de fotografías. Las pruebas
validan UUID, slot, hash, fecha original y MIME del multipart real de Dio.

`remoteVerified` sin recibo válido se recupera mediante la cola, no se acepta como
confirmación. La recuperación de un recibo coincidente tampoco modifica fotografías
locales que pertenezcan a otro usuario, revisión o slot: conserva el recibo y expone
un conflicto de identidad. Un estado remoto `inactive` sin recibo local completo queda
fuera del pipeline ordinario, incluso cuando se solicita reintentar.

### Resultado de la ejecución local

- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub --reporter compact`: **640 pruebas aprobadas**,
  incluidas **35 nuevas** de sincronización/contrato de Ausente.
- `git diff --check`: sin errores.
- Se conserva `1.0.17+117`; no se desplegó API ni modificó producción.
- Compilación QA debug aprobada: `flutter build apk --debug --flavor qa -t lib/main_qa.dart --no-pub`.
  Package verificado con `aapt`: `com.aquafim.ddr001diag.qa`, `1.0.17-qa`, build 117.
  Esta variante usa fixtures sin red; no es una distribución productiva.
- No se ejecutó aceptación física ni integración contra servidor desplegado.

### Archivos modificados en la app

- `docs/inactive_no_hydrant_closure_contract.md`
- `lib/core/network/api_exception.dart`
- `lib/core/services/app_state.dart`
- `lib/data/local/recovery_coordinator.dart`
- `lib/data/local/visual_inspection_repository.dart`
- `lib/domain/sync/rv_sync_truth.dart`
- `lib/features/diagnostics/rv_diagnostic_export_service.dart`
- `lib/features/home/all_reviews_page.dart`
- `lib/features/home/rv_work_dashboard.dart`
- `lib/features/hydrants/hydrant_pages.dart`
- `lib/features/inspections/data/inactive_closure_sync.dart`
- `lib/features/inspections/data/inspection_remote_repository.dart`
- `lib/features/inspections/data/inspection_sync_coordinator.dart`
- `lib/features/inspections/data/rv_draft_repository.dart`
- `lib/features/inspections/domain/rv_draft.dart`
- `lib/features/inspections/domain/rv_inactive_contract.dart`
- `lib/features/inspections/domain/rv_validator.dart`
- `lib/features/inspections/presentation/rv_inactive_closure_dialog.dart`
- `lib/features/inspections/presentation/rv_inspection_controller.dart`
- `lib/features/inspections/presentation/rv_summary_page.dart`
- `lib/features/map/map_page.dart`
- `lib/features/visual_reports/presentation/rv_visual_report_page.dart`
- `lib/qa/qa_app.dart`
- `test/inspections/rv_inactive_closure_test.dart`
- `test/inspections/rv_inactive_sync_test.dart`
- `test/operations/rv_operational_hardening_test.dart`
- `test/widgets/all_reviews_page_test.dart`
