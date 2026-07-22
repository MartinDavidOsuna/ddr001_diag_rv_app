# Contrato local para DDR001 API futura

No implementa transporte remoto.

## Fuentes de verdad

Hydrant, VisualInspection, FunctionalInspection, FunctionalReportEligibility, InstrumentRecord, InstrumentSnapshot, ValveRecord, ReducerRun, AlarmAttemptRecord, MeasurementSeries, MeasurementReading, InspectionPhoto/MediaAsset, TraceEvent y OperationJournal.

## Proyecciones

InspectionSummary, filtros, contadores, ficha y resumen de jornada. Nunca deben sustituir el documento fuente.

## Derivados

Cálculos tipados, resultado agregado, `allSynchronized` y acciones disponibles.

## Sobre sincronización

Toda entidad nueva debe preparar: id, schemaVersion, revision, baseRevision, createdAt, updatedAt, deletedAt, actorId, brigadeId, deviceId, correlationId e idempotencyKey. `SyncQueueItem` incorpora dependencias, tombstone, estado de conflicto y próximo intento. `SyncTransport` queda como interfaz sin implementación.

Los reportes finalizados son inmutables. Las correcciones son revisiones y las eliminaciones son lógicas. ISO-8601 UTC, enums como strings y read-old/write-new son obligatorios. Fotos requieren hash; uploadedUnverified no equivale a synchronized.
