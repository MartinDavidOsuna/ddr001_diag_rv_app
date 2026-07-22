import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/sync/sync_queue_item.dart';

abstract final class Stage4Fixtures {
  static final timestamp = DateTime.utc(2026, 7, 15, 18);

  static OperationJournalEntry journal({
    String id = 'operation-1',
    JournalStatus status = JournalStatus.prepared,
    JournalOperationType type = JournalOperationType.createVisualAndFunctional,
  }) => OperationJournalEntry(
    operationId: id,
    operationType: type,
    entityIds: const ['rv-1', 'rf-1'],
    status: status,
    preparedAt: timestamp,
    actor: 'inspector-1',
    deviceId: 'device-1',
    correlationId: 'correlation-1',
  );

  static SyncQueueItem syncItem({
    required String id,
    SyncQueueStatus status = SyncQueueStatus.pending,
    List<String> dependencies = const [],
  }) => SyncQueueItem(
    id: id,
    entityType: 'functionalInspection',
    entityId: id,
    dependencyIds: dependencies,
    idempotencyKey: 'functionalInspection:$id:1',
    status: status,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
