enum SyncQueueStatus {
  pending,
  processing,
  synced,
  failedRetryable,
  failedPermanent,
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    this.inspectionId,
    this.hydrantId,
    this.operation = 'upsert',
    this.dependencyIds = const [],
    this.idempotencyKey = '',
    this.payloadVersion = 1,
    this.revision = 1,
    this.baseRevision = 0,
    this.tombstone = false,
    this.status = SyncQueueStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.conflictStatus = 'none',
    this.correlationId = '',
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });
  final String id, entityType, entityId, operation, idempotencyKey;
  final String conflictStatus, correlationId;
  final String? inspectionId, hydrantId, lastError;
  final List<String> dependencyIds;
  final SyncQueueStatus status;
  final int attempts, schemaVersion, payloadVersion, revision, baseRevision;
  final bool tombstone;
  final DateTime createdAt, updatedAt;
  final DateTime? nextAttemptAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'inspectionId': inspectionId,
    'hydrantId': hydrantId,
    'operation': operation,
    'dependencyIds': dependencyIds,
    'idempotencyKey': idempotencyKey,
    'payloadVersion': payloadVersion,
    'revision': revision,
    'baseRevision': baseRevision,
    'tombstone': tombstone,
    'status': status.name,
    'attempts': attempts,
    'lastError': lastError,
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    'conflictStatus': conflictStatus,
    'correlationId': correlationId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory SyncQueueItem.fromJson(Map<String, dynamic> j) => SyncQueueItem(
    id: j['id'] as String? ?? '',
    entityType: j['entityType'] as String? ?? 'legacy',
    entityId: j['entityId'] as String? ?? '',
    inspectionId: j['inspectionId'] as String?,
    hydrantId: j['hydrantId'] as String?,
    operation: j['operation'] as String? ?? 'upsert',
    dependencyIds: (j['dependencyIds'] as List? ?? const [])
        .map((v) => '$v')
        .toList(),
    idempotencyKey:
        j['idempotencyKey'] as String? ?? '${j['entityType']}:${j['entityId']}',
    payloadVersion: j['payloadVersion'] as int? ?? 1,
    revision: j['revision'] as int? ?? 1,
    baseRevision: j['baseRevision'] as int? ?? 0,
    tombstone: j['tombstone'] as bool? ?? false,
    status: _status(j['status']),
    attempts: j['attempts'] as int? ?? 0,
    lastError: j['lastError'] as String?,
    nextAttemptAt: DateTime.tryParse(
      j['nextAttemptAt'] as String? ?? '',
    )?.toUtc(),
    conflictStatus: j['conflictStatus'] as String? ?? 'none',
    correlationId: j['correlationId'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
  static SyncQueueStatus _status(Object? name) {
    for (final value in SyncQueueStatus.values) {
      if (value.name == name) return value;
    }
    return SyncQueueStatus.pending;
  }
}
