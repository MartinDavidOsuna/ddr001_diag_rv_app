enum IntegritySeverity { info, warning, high, critical }

enum IntegrityIssueType {
  activeIndexWithoutDocument,
  activeDocumentWithoutIndex,
  mutableCompletedReport,
  openSeriesWithoutReport,
  seriesWithoutInstrument,
  readingWithoutSeries,
  photoWithoutFile,
  fileWithoutDocument,
  missingThumbnail,
  photoWithoutQueue,
  queueWithoutEntity,
  incompleteJournal,
  partialVisualFunctionalCreation,
  corruptJson,
  invalidRevisionReference,
  resultWithoutReport,
  retiredInstrumentInActiveSeries,
}

enum RecoveryAction {
  recreateIndex,
  removeOrphanIndex,
  regenerateThumbnail,
  enqueuePhoto,
  markMissingLocal,
  completeJournalOperation,
  pauseInterruptedSeries,
  quarantineDocument,
  manualReview,
}

class IntegrityIssue {
  const IntegrityIssue({
    required this.id,
    required this.type,
    required this.severity,
    required this.entityType,
    required this.entityId,
    required this.userMessage,
    required this.technicalMessage,
    required this.recommendedAction,
    this.repairableAutomatically = false,
  });
  final String id, entityType, entityId, userMessage, technicalMessage;
  final IntegrityIssueType type;
  final IntegritySeverity severity;
  final RecoveryAction recommendedAction;
  final bool repairableAutomatically;
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'severity': severity.name,
    'entityType': entityType,
    'entityId': entityId,
    'userMessage': userMessage,
    'technicalMessage': technicalMessage,
    'recommendedAction': recommendedAction.name,
    'repairableAutomatically': repairableAutomatically,
  };
}

class IntegrityAuditReport {
  const IntegrityAuditReport({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required this.issues,
    this.schemaVersion = 1,
  });
  final String id;
  final DateTime startedAt, completedAt;
  final List<IntegrityIssue> issues;
  final int schemaVersion;
  bool get requiresReview => issues.any(
    (issue) =>
        issue.severity == IntegritySeverity.high ||
        issue.severity == IntegritySeverity.critical,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'issues': issues.map((issue) => issue.toJson()).toList(),
    'schemaVersion': schemaVersion,
  };
}
