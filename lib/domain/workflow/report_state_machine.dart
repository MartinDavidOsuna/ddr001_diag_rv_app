import 'package:uuid/uuid.dart';

enum ReportState {
  draft,
  ready,
  inProgress,
  paused,
  suspended,
  completed,
  cancelled,
  requiresRepeat,
  pendingReview,
  synced,
}

enum ReportTransitionDecision { allowed, rejected }

class ReportTransitionRequest {
  const ReportTransitionRequest({
    required this.reportId,
    required this.reportType,
    required this.currentState,
    required this.requestedState,
    required this.actor,
    required this.role,
    required this.deviceId,
    required this.timestamp,
    required this.correlationId,
    this.reason = '',
  });
  final String reportId, reportType, actor, role, deviceId, correlationId;
  final String reason;
  final ReportState currentState, requestedState;
  final DateTime timestamp;
}

class ReportTransitionResult {
  const ReportTransitionResult({
    required this.decision,
    required this.previousState,
    required this.nextState,
    required this.reasonCode,
    required this.userMessage,
    required this.traceEventId,
    this.persisted = false,
  });
  final ReportTransitionDecision decision;
  final ReportState previousState, nextState;
  final String reasonCode, userMessage, traceEventId;
  final bool persisted;
  bool get allowed => decision == ReportTransitionDecision.allowed;
  ReportTransitionResult markPersisted() => ReportTransitionResult(
    decision: decision,
    previousState: previousState,
    nextState: nextState,
    reasonCode: reasonCode,
    userMessage: userMessage,
    traceEventId: traceEventId,
    persisted: true,
  );
}

class ReportStateMachine {
  const ReportStateMachine();

  static const _allowed = <ReportState, Set<ReportState>>{
    ReportState.draft: {
      ReportState.ready,
      ReportState.inProgress,
      ReportState.cancelled,
    },
    ReportState.ready: {ReportState.inProgress, ReportState.cancelled},
    ReportState.inProgress: {
      ReportState.paused,
      ReportState.suspended,
      ReportState.pendingReview,
      ReportState.completed,
      ReportState.cancelled,
    },
    ReportState.paused: {ReportState.inProgress},
    ReportState.suspended: {ReportState.inProgress, ReportState.cancelled},
    ReportState.pendingReview: {
      ReportState.completed,
      ReportState.requiresRepeat,
    },
    ReportState.completed: {ReportState.synced, ReportState.requiresRepeat},
    ReportState.requiresRepeat: {},
    ReportState.cancelled: {},
    ReportState.synced: {},
  };

  ReportTransitionResult evaluate(ReportTransitionRequest request) {
    final same = request.currentState == request.requestedState;
    final allowed =
        !same &&
        (_allowed[request.currentState] ?? const {}).contains(
          request.requestedState,
        );
    final needsReason =
        request.requestedState == ReportState.cancelled ||
        request.requestedState == ReportState.suspended ||
        request.requestedState == ReportState.requiresRepeat;
    final missingReason = needsReason && request.reason.trim().isEmpty;
    final accepted = allowed && !missingReason;
    return ReportTransitionResult(
      decision: accepted
          ? ReportTransitionDecision.allowed
          : ReportTransitionDecision.rejected,
      previousState: request.currentState,
      nextState: accepted ? request.requestedState : request.currentState,
      reasonCode: missingReason
          ? 'reasonRequired'
          : same
          ? 'sameState'
          : allowed
          ? 'transitionAllowed'
          : 'invalidTransition',
      userMessage: missingReason
          ? 'Captura el motivo para continuar.'
          : same
          ? 'El reporte ya se encuentra en ese estado.'
          : allowed
          ? 'Estado actualizado correctamente.'
          : 'Este cambio de estado no está permitido.',
      traceEventId: const Uuid().v4(),
    );
  }
}

class ReportRevisionMetadata {
  const ReportRevisionMetadata({
    required this.revisionOfReportId,
    required this.revisionNumber,
    this.previousRevisionId,
    required this.revisionReason,
    required this.createdBy,
    required this.createdAt,
    this.supervisorReviewRequired = true,
    this.approvedBy,
    this.approvedAt,
    this.activeRevision = true,
    this.schemaVersion = 1,
  });
  final String revisionOfReportId, revisionReason, createdBy;
  final String? previousRevisionId, approvedBy;
  final int revisionNumber, schemaVersion;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final bool supervisorReviewRequired, activeRevision;
  Map<String, dynamic> toJson() => {
    'revisionOfReportId': revisionOfReportId,
    'revisionNumber': revisionNumber,
    'previousRevisionId': previousRevisionId,
    'revisionReason': revisionReason,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'supervisorReviewRequired': supervisorReviewRequired,
    'approvedBy': approvedBy,
    'approvedAt': approvedAt?.toUtc().toIso8601String(),
    'activeRevision': activeRevision,
    'schemaVersion': schemaVersion,
  };
}
