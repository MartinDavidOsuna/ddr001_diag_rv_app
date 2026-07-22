# Integridad y recuperación local — Etapa 4B

Hive y filesystem no forman una transacción atómica. `OperationJournalEntry` registra fases prepared, documentsWritten, indexesWritten, filesWritten, queueWritten, committed, needsRecovery, failed y quarantined.

Al arranque `RecoveryCoordinator.runLightweight` audita índices, JSON, series, instrumentos, fotos, colas y journals. Solo ejecuta reparaciones inequívocas: retirar índice huérfano, recrear trabajo de medios y confirmar un journal que ya alcanzó queueWritten. Los demás casos quedan `needsRecovery` o revisión manual.

`QuarantineRepository` copia íntegramente contenido corrupto, caja/key, timestamp, error y SHA-256. Nunca elimina el documento fuente ni almacena credenciales. `IntegrityAuditReport` es serializable y la UI debe mostrar únicamente mensajes accionables.

`MediaReconciliationService` conserva originales, detecta archivo/miniatura/cola faltante, corrige uploadedUnverified incoherente y nunca borra una foto verified local.

## Recuperación por fase

- `prepared`: si no existe ninguna escritura observable se marca fallida de forma compensada; cualquier escritura parcial queda `needsRecovery`.
- `documentsWritten`/`indexesWritten`: solo se reconstruye o retira un índice cuando documento, hidrante y estado son inequívocos.
- `filesWritten`: se conservan archivos y se solicita revisión si no existe relación documental segura.
- `queueWritten`: solo se confirma `committed` cuando documentos y colas declarados existen.
- `needsRecovery`/`failed`: no se reintenta destructivamente ni se inventan documentos.
- `quarantined`: permanece aislado.

La política cubre todos los `JournalOperationType`. `capturePhoto` puede reencolarse si documento y original existen; si falta alguno conserva toda evidencia y solicita revisión.

## Miniaturas y huérfanos

`ThumbnailRegenerationService` excluye ejecuciones simultáneas por photoId, valida el original, escribe un temporal, renombra, confirma el archivo, actualiza el documento y registra journal/traza. Un fallo de decodificación se clasifica como original corrupto y no reemplaza ni elimina el archivo.

`OrphanMediaScanner` recorre únicamente `ApplicationDocuments/evidence`, sin seguir enlaces. Registra originales, miniaturas y temporales sin documento; solo expone asociación cuando el ID resulta inequívoco y nunca elimina automáticamente.

La vista Auditoría técnica está restringida a administrador/supervisor local, muestra información accionable y exporta JSON/texto al portapapeles sin credenciales.
