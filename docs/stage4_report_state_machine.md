# Máquina de estados RV/RF — Etapa 4B

`ReportStateMachine` es la autoridad común para transiciones nuevas. Recibe reporte, tipo, estado actual/solicitado, actor, rol, dispositivo, motivo, timestamp y correlación; devuelve decisión, estados, código, mensaje controlado, ID de traza y confirmación de persistencia.

Permitidas: draft→ready/inProgress/cancelled; ready→inProgress/cancelled; inProgress→paused/suspended/pendingReview/completed/cancelled; paused→inProgress; suspended→inProgress/cancelled; pendingReview→completed/requiresRepeat; completed→synced/requiresRepeat.

Prohibidas: completed→inProgress/draft, synced→draft/inProgress, cancelled→inProgress. Suspensión, cancelación y repetición exigen motivo. Los estados históricos RV se proyectan sin reescribir documentos antiguos.

Un reporte completed/synced es inmutable. Una corrección crea un documento nuevo con `revisionOfReportId`, `revisionNumber`, `previousRevisionId`, motivo, autor, fecha, revisión activa y revisión supervisora requerida. No se modifica el original.

`CurrentReportRevisionResolver` reconstruye la cadena RV/RF a partir de referencias y orden; no confía en `activeRevision`. Una raíz y una hoja no cancelada son obligatorias. Bifurcaciones, ciclos, referencias faltantes o numeración no creciente producen resolución ambigua e `IntegrityIssue`; ningún documento se descarta ni se elige silenciosamente.
