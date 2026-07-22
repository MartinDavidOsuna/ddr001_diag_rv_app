enum JournalOperationType {
  createHydrant,
  createVisualReport,
  createFunctionalReport,
  createVisualAndFunctional,
  finalizeVisualReport,
  finalizeFunctionalReport,
  createRevision,
  capturePhoto,
  deletePhoto,
  createTemporaryHydrant,
  repairIndex,
  enqueueSync,
}

enum JournalStatus {
  prepared,
  documentsWritten,
  indexesWritten,
  filesWritten,
  queueWritten,
  committed,
  needsRecovery,
  failed,
  quarantined,
}

class OperationJournalEntry {
  const OperationJournalEntry({
    required this.operationId,
    required this.operationType,
    this.entityIds = const [],
    this.documentWrites = const [],
    this.indexWrites = const [],
    this.fileWrites = const [],
    this.queueWrites = const [],
    this.status = JournalStatus.prepared,
    required this.preparedAt,
    this.documentsWrittenAt,
    this.indexesWrittenAt,
    this.filesWrittenAt,
    this.queueWrittenAt,
    this.committedAt,
    this.needsRecoveryAt,
    this.lastError,
    this.recoveryAttempts = 0,
    required this.actor,
    required this.deviceId,
    required this.correlationId,
    this.schemaVersion = 1,
  });
  final String operationId, actor, deviceId, correlationId;
  final JournalOperationType operationType;
  final List<String> entityIds, documentWrites, indexWrites, fileWrites;
  final List<String> queueWrites;
  final JournalStatus status;
  final DateTime preparedAt;
  final DateTime? documentsWrittenAt, indexesWrittenAt, filesWrittenAt;
  final DateTime? queueWrittenAt, committedAt, needsRecoveryAt;
  final String? lastError;
  final int recoveryAttempts, schemaVersion;

  OperationJournalEntry advance(JournalStatus next, {String? error}) {
    final now = DateTime.now().toUtc();
    return OperationJournalEntry(
      operationId: operationId,
      operationType: operationType,
      entityIds: entityIds,
      documentWrites: documentWrites,
      indexWrites: indexWrites,
      fileWrites: fileWrites,
      queueWrites: queueWrites,
      status: next,
      preparedAt: preparedAt,
      documentsWrittenAt: next == JournalStatus.documentsWritten
          ? now
          : documentsWrittenAt,
      indexesWrittenAt: next == JournalStatus.indexesWritten
          ? now
          : indexesWrittenAt,
      filesWrittenAt: next == JournalStatus.filesWritten ? now : filesWrittenAt,
      queueWrittenAt: next == JournalStatus.queueWritten ? now : queueWrittenAt,
      committedAt: next == JournalStatus.committed ? now : committedAt,
      needsRecoveryAt: next == JournalStatus.needsRecovery
          ? now
          : needsRecoveryAt,
      lastError: error ?? lastError,
      recoveryAttempts:
          recoveryAttempts + (next == JournalStatus.needsRecovery ? 1 : 0),
      actor: actor,
      deviceId: deviceId,
      correlationId: correlationId,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'operationType': operationType.name,
    'entityIds': entityIds,
    'documentWrites': documentWrites,
    'indexWrites': indexWrites,
    'fileWrites': fileWrites,
    'queueWrites': queueWrites,
    'status': status.name,
    'preparedAt': preparedAt.toUtc().toIso8601String(),
    'documentsWrittenAt': documentsWrittenAt?.toUtc().toIso8601String(),
    'indexesWrittenAt': indexesWrittenAt?.toUtc().toIso8601String(),
    'filesWrittenAt': filesWrittenAt?.toUtc().toIso8601String(),
    'queueWrittenAt': queueWrittenAt?.toUtc().toIso8601String(),
    'committedAt': committedAt?.toUtc().toIso8601String(),
    'needsRecoveryAt': needsRecoveryAt?.toUtc().toIso8601String(),
    'lastError': lastError,
    'recoveryAttempts': recoveryAttempts,
    'actor': actor,
    'deviceId': deviceId,
    'correlationId': correlationId,
    'schemaVersion': schemaVersion,
  };

  factory OperationJournalEntry.fromJson(Map<String, dynamic> json) =>
      OperationJournalEntry(
        operationId: json['operationId'] as String? ?? '',
        operationType: _enum(
          JournalOperationType.values,
          json['operationType'],
          JournalOperationType.createHydrant,
        ),
        entityIds: _strings(json['entityIds']),
        documentWrites: _strings(json['documentWrites']),
        indexWrites: _strings(json['indexWrites']),
        fileWrites: _strings(json['fileWrites']),
        queueWrites: _strings(json['queueWrites']),
        status: _enum(
          JournalStatus.values,
          json['status'],
          JournalStatus.failed,
        ),
        preparedAt: _date(json['preparedAt']),
        documentsWrittenAt: _nullableDate(json['documentsWrittenAt']),
        indexesWrittenAt: _nullableDate(json['indexesWrittenAt']),
        filesWrittenAt: _nullableDate(json['filesWrittenAt']),
        queueWrittenAt: _nullableDate(json['queueWrittenAt']),
        committedAt: _nullableDate(json['committedAt']),
        needsRecoveryAt: _nullableDate(json['needsRecoveryAt']),
        lastError: json['lastError'] as String?,
        recoveryAttempts: json['recoveryAttempts'] as int? ?? 0,
        actor: json['actor'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        correlationId: json['correlationId'] as String? ?? '',
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;
List<String> _strings(Object? raw) =>
    (raw as List? ?? const []).map((value) => '$value').toList();
DateTime _date(Object? raw) =>
    DateTime.tryParse(raw as String? ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
DateTime? _nullableDate(Object? raw) =>
    DateTime.tryParse(raw as String? ?? '')?.toUtc();
