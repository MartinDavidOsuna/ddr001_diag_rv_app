import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/inspections/visual_inspection.dart';
import '../../domain/models/app_models.dart';
import '../../domain/workflow/report_state_machine.dart';
import '../../domain/integrity/operation_journal.dart';
import 'operation_journal_repository.dart';

class VisualInspectionRepository {
  VisualInspectionRepository({required this.documents, required this.index});

  final Box<String> documents;
  final Box<String> index;

  String _indexKey(String hydrantId) => '$hydrantId:f02A';

  bool hasLocalInspection(String hydrantId) {
    final id = index.get(_indexKey(hydrantId));
    return id != null && documents.containsKey(id);
  }

  List<VisualInspection> forHydrant(String hydrantId) {
    final values = <VisualInspection>[];
    for (final raw in documents.values) {
      try {
        final value = VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (value.hydrantId == hydrantId) values.add(value);
      } on Object {
        continue;
      }
    }
    values.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  Future<VisualInspection> openOrCreate(Hydrant hydrant, AppUser user) async {
    final existingId = index.get(_indexKey(hydrant.id));
    if (existingId != null) {
      final raw = documents.get(existingId);
      if (raw != null) {
        return VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
      }
    }
    if (hydrant.f02a.status == InspectionStatus.completed) {
      for (final raw in documents.values) {
        try {
          final candidate = VisualInspection.fromJson(
            VersionedJsonCodec.decode(raw).payload,
          );
          if (candidate.hydrantId == hydrant.id &&
              candidate.status == InspectionStatus.completed) {
            return candidate;
          }
        } on FormatException {
          continue;
        }
      }
    }
    final now = DateTime.now().toUtc();
    final inspection = VisualInspection(
      id: const Uuid().v4(),
      hydrantId: hydrant.id,
      assignmentId: hydrant.source == HydrantSource.assigned
          ? hydrant.id
          : null,
      source: hydrant.source,
      inspectorId: user.id,
      inspectorName: user.fullName,
      brigadeId: user.brigadeId,
      brigadeName: user.brigadeName,
      deviceId: user.deviceId,
      startedAt: now,
      createdAt: now,
      createdBy: user.id,
      updatedAt: now,
      updatedBy: user.id,
      identification: HydrantIdentification(assignedCode: hydrant.code),
    );
    await save(inspection);
    await index.put(_indexKey(hydrant.id), inspection.id);
    return inspection;
  }

  Future<void> save(VisualInspection inspection) async {
    final encoded = VersionedJsonCodec.encode(
      schemaVersion: inspection.schemaVersion,
      payload: inspection.toJson(),
    );
    final previous = documents.get(inspection.id);
    if (previous != null) {
      final stored = VisualInspection.fromJson(
        VersionedJsonCodec.decode(previous).payload,
      );
      if (stored.status == InspectionStatus.completed) {
        throw StateError(
          'El REPORTE VISUAL finalizado es inmutable. Crea una revisión.',
        );
      }
      if (stored.status != inspection.status) {
        final previousState = stored.status == InspectionStatus.completed
            ? ReportState.completed
            : stored.status == InspectionStatus.pending
            ? ReportState.draft
            : ReportState.inProgress;
        final nextState = inspection.status == InspectionStatus.completed
            ? ReportState.completed
            : inspection.status == InspectionStatus.pending
            ? ReportState.draft
            : ReportState.inProgress;
        final transition = const ReportStateMachine().evaluate(
          ReportTransitionRequest(
            reportId: inspection.id,
            reportType: 'f02A',
            currentState: previousState,
            requestedState: nextState,
            actor: inspection.updatedBy,
            role: 'inspector',
            deviceId: inspection.deviceId,
            timestamp: DateTime.now().toUtc(),
            correlationId: const Uuid().v4(),
          ),
        );
        if (!transition.allowed) throw StateError(transition.userMessage);
      }
    }
    if (previous != null &&
        VersionedJsonCodec.decode(previous).schemaVersion !=
            inspection.schemaVersion) {
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      await documents.put('${inspection.id}:previous:$stamp', previous);
    }
    await documents.put(inspection.id, encoded);
    final confirmed = documents.get(inspection.id);
    if (confirmed == null) {
      throw StateError('No fue posible confirmar la escritura del borrador.');
    }
    VersionedJsonCodec.decode(confirmed);
  }

  Future<VisualInspection> createRevision(
    VisualInspection original,
    AppUser supervisor,
    String reason,
  ) async {
    if (original.status != InspectionStatus.completed) {
      throw StateError('Solo un REPORTE VISUAL finalizado admite revisión.');
    }
    if (!supervisor.role.toLowerCase().contains('supervisor')) {
      throw StateError('La revisión requiere rol supervisor local.');
    }
    if (reason.trim().isEmpty) throw StateError('El motivo es obligatorio.');
    final now = DateTime.now().toUtc();
    final json = original.toJson()
      ..['id'] = const Uuid().v4()
      ..['status'] = InspectionStatus.inProgress.name
      ..['currentStep'] = 1
      ..['visualFlowVersion'] = 2
      ..['publicComponentIndex'] = 0
      ..['privateComponentIndex'] = 0
      ..['flowMeterComponentConfirmed'] = false
      ..['flowMeterComponentReviewedBy'] = null
      ..['flowMeterComponentReviewedAt'] = null
      ..['completedAt'] = null
      ..['createdAt'] = now.toIso8601String()
      ..['createdBy'] = supervisor.id
      ..['updatedAt'] = now.toIso8601String()
      ..['updatedBy'] = supervisor.id
      ..['revisionOfReportId'] = original.revisionOfReportId ?? original.id
      ..['revisionNumber'] = original.revisionNumber + 1
      ..['previousRevisionId'] = original.id
      ..['revisionReason'] = reason.trim()
      ..['activeRevision'] = true
      ..['supervisorReviewRequired'] = true;
    json['componentInspections'] = [
      for (final raw in json['componentInspections'] as List? ?? const [])
        {
          ...Map<String, dynamic>.from(raw as Map),
          'explicitlyConfirmed': false,
          'suggestedDefaultsApplied': false,
          'reviewStatus': 'pending',
          'reviewedBy': null,
          'reviewedAt': null,
          'quickReviewApplied': false,
          'legacyRequiresConfirmation': true,
        },
    ];
    final revision = VisualInspection.fromJson(json);
    await save(revision);
    await index.put(_indexKey(revision.hydrantId), revision.id);
    return revision;
  }

  Future<void> finalize(VisualInspection inspection) async {
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    var operation = OperationJournalEntry(
      operationId: const Uuid().v4(),
      operationType: JournalOperationType.finalizeVisualReport,
      entityIds: [inspection.id],
      documentWrites: [inspection.id],
      indexWrites: [_indexKey(inspection.hydrantId)],
      preparedAt: DateTime.now().toUtc(),
      actor: inspection.updatedBy,
      deviceId: inspection.deviceId,
      correlationId: inspection.id,
    );
    await journal.save(operation);
    try {
      await save(inspection);
      final confirmed = documents.get(inspection.id);
      if (confirmed == null ||
          VisualInspection.fromJson(
                VersionedJsonCodec.decode(confirmed).payload,
              ).status !=
              InspectionStatus.completed) {
        throw StateError('No fue posible confirmar la finalización local.');
      }
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      await index.delete(_indexKey(inspection.hydrantId));
      await journal.save(operation.advance(JournalStatus.committed));
    } on Object catch (error) {
      await journal.save(
        operation.advance(JournalStatus.needsRecovery, error: '$error'),
      );
      rethrow;
    }
  }
}
