import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../core/security/local_data_scope.dart';
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
  LocalDataScope? _scope;
  bool _scopeConfigured = false;

  void setAccessScope(LocalDataScope? scope) {
    _scope = scope;
    _scopeConfigured = true;
  }

  bool _canAccess(VisualInspection value) {
    if (!_scopeConfigured) return true;
    final scope = _scope;
    if (scope == null || !scope.isUsable) return false;
    if (scope.isAdministrator) return true;
    final rawScope = value.unknownFields['dataScope'];
    if (rawScope is! Map) return false;
    final storedScope = Map<String, dynamic>.from(rawScope);
    if (storedScope['environment'] != scope.environment ||
        storedScope['accountId'] != scope.accountId) {
      return false;
    }
    return scope.owns(ownerUserId: value.createdBy) ||
        scope.owns(ownerUserId: value.inspectorId);
  }

  String _indexKey(String hydrantId) {
    final prefix = _scope?.namespace;
    return prefix == null ? '$hydrantId:f02A' : '$prefix/$hydrantId/f02A';
  }

  List<VisualInspection> accessible() {
    final values = <VisualInspection>[];
    for (final raw in documents.values) {
      try {
        final value = VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (_canAccess(value)) values.add(value);
      } on Object {
        continue;
      }
    }
    return values;
  }

  /// Removes only index entries that cannot represent active work anymore.
  /// Inspection documents are deliberately preserved for recovery/history.
  Future<int> reconcileActiveIndex() async {
    final staleKeys = <Object>[];
    for (final entry in index.toMap().entries) {
      final id = entry.value;
      if (id.isEmpty) {
        staleKeys.add(entry.key);
        continue;
      }
      final raw = documents.get(id);
      if (raw == null) {
        staleKeys.add(entry.key);
        continue;
      }
      try {
        final inspection = VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (inspection.status == InspectionStatus.completed ||
            entry.key != _indexKey(inspection.hydrantId)) {
          staleKeys.add(entry.key);
        }
      } on Object {
        // Keep ambiguous/corrupt entries for the integrity audit and quarantine.
      }
    }
    if (staleKeys.isNotEmpty) await index.deleteAll(staleKeys);
    return staleKeys.length;
  }

  Future<void> replaceActiveVisualIndex(
    Map<String, String> canonicalByKey,
  ) async {
    final ownedKeys = index.keys
        .where((key) => '$key'.endsWith(':f02A') || '$key'.endsWith('/f02A'))
        .toList(growable: false);
    if (ownedKeys.isNotEmpty) await index.deleteAll(ownedKeys);
    await index.putAll(canonicalByKey);
  }

  bool hasLocalInspection(String hydrantId) {
    final id = index.get(_indexKey(hydrantId));
    return id != null && findById(id) != null;
  }

  VisualInspection? findById(String id) {
    final raw = documents.get(id);
    if (raw == null) return null;
    try {
      final value = VisualInspection.fromJson(
        VersionedJsonCodec.decode(raw).payload,
      );
      return _canAccess(value) ? value : null;
    } on Object {
      return null;
    }
  }

  List<VisualInspection> forHydrant(String hydrantId) {
    final values = <VisualInspection>[];
    for (final value in accessible()) {
      if (value.hydrantId == hydrantId) values.add(value);
    }
    values.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  Future<VisualInspection> openOrCreate(Hydrant hydrant, AppUser user) async {
    if (_scopeConfigured &&
        (_scope == null || !_scope!.owns(ownerUserId: user.id))) {
      throw StateError('La sesión activa no autoriza crear este borrador.');
    }
    final existingId = index.get(_indexKey(hydrant.id));
    if (existingId != null) {
      final raw = documents.get(existingId);
      if (raw != null) {
        final existing = VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (existing.status != InspectionStatus.completed) return existing;
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
      unknownFields: {
        'dataScope': {
          'environment': _scope?.environment ?? 'legacy',
          'accountId': _scope?.accountId ?? 'legacy',
          'ownerUserId': user.id,
          'brigadeId': user.brigadeId,
        },
      },
    );
    await save(inspection);
    await index.put(_indexKey(hydrant.id), inspection.id);
    return inspection;
  }

  Future<void> save(VisualInspection inspection) async {
    if (_scopeConfigured && !_canAccess(inspection)) {
      throw StateError('La sesión activa no autoriza modificar este borrador.');
    }
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
    if (inspection.status == InspectionStatus.completed) {
      final key = _indexKey(inspection.hydrantId);
      if (index.get(key) == inspection.id) await index.delete(key);
    }
  }

  /// Updates only the embedded RV synchronization envelope of a completed
  /// report. Technical answers, evidence references and completion timestamps
  /// remain exactly as originally persisted.
  Future<void> saveCompletedSyncMetadata({
    required String inspectionId,
    required String storageKey,
    required Object metadata,
  }) async {
    final stored = findById(inspectionId);
    if (stored == null || stored.status != InspectionStatus.completed) {
      throw StateError('El documento no es un REPORTE VISUAL finalizado.');
    }
    final updated = stored.copyWith(
      unknownFields: {...stored.unknownFields, storageKey: metadata},
    );
    await documents.put(
      inspectionId,
      VersionedJsonCodec.encode(
        schemaVersion: updated.schemaVersion,
        payload: updated.toJson(),
      ),
    );
  }

  Future<void> createRevisionClone(VisualInspection revision) async {
    if (documents.containsKey(revision.id)) {
      throw StateError('La revisión local ya existe.');
    }
    await documents.put(
      revision.id,
      VersionedJsonCodec.encode(
        schemaVersion: revision.schemaVersion,
        payload: revision.toJson(),
      ),
    );
    await index.put(_indexKey(revision.hydrantId), revision.id);
  }

  Future<void> deleteLocalDraft(String id, {required String creatorId}) async {
    final inspection = findById(id);
    if (inspection == null) {
      throw StateError('No se encontró el borrador local.');
    }
    if (inspection.createdBy != creatorId &&
        inspection.inspectorId != creatorId) {
      throw StateError('Sólo el creador puede eliminar este borrador.');
    }
    if (inspection.status == InspectionStatus.completed) {
      throw StateError('Una revisión finalizada no puede eliminarse.');
    }
    await documents.delete(id);
    final key = _indexKey(inspection.hydrantId);
    if (index.get(key) == id) await index.delete(key);
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
