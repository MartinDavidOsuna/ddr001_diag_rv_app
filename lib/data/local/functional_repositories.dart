import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/functional/functional_models.dart';
import '../../domain/models/app_models.dart';
import '../../domain/workflow/report_state_machine.dart';
import '../../domain/integrity/operation_journal.dart';
import 'operation_journal_repository.dart';

class FunctionalEligibilityRepository {
  const FunctionalEligibilityRepository(this.documents);
  final Box<String> documents;
  FunctionalReportEligibility? find(String hydrantId) {
    final raw = documents.get(hydrantId);
    return raw == null
        ? null
        : FunctionalReportEligibility.fromJson(
            VersionedJsonCodec.decode(raw).payload,
          );
  }

  Future<void> save(FunctionalReportEligibility value) => documents.put(
    value.hydrantId,
    VersionedJsonCodec.encode(
      schemaVersion: value.schemaVersion,
      payload: value.toJson(),
    ),
  );
}

class FunctionalInspectionRepository {
  const FunctionalInspectionRepository({
    required this.documents,
    required this.index,
  });
  final Box<String> documents, index;
  String indexKey(String hydrantId) => '$hydrantId:f02B';
  FunctionalInspection? activeFor(String hydrantId) {
    final id = index.get(indexKey(hydrantId));
    final raw = id == null ? null : documents.get(id);
    return raw == null
        ? null
        : FunctionalInspection.fromJson(VersionedJsonCodec.decode(raw).payload);
  }

  bool hasActive(String hydrantId) => activeFor(hydrantId) != null;
  List<FunctionalInspection> forHydrant(String hydrantId) {
    final values = <FunctionalInspection>[];
    for (final raw in documents.values) {
      try {
        final item = FunctionalInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (item.hydrantId == hydrantId) values.add(item);
      } on Object {
        continue;
      }
    }
    values.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return values;
  }

  Future<FunctionalInspection> openOrCreate(
    Hydrant hydrant,
    AppUser user, {
    String? visualInspectionId,
  }) async {
    final active = activeFor(hydrant.id);
    if (active != null) return active;
    final now = DateTime.now().toUtc();
    final value = FunctionalInspection(
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
      updatedAt: now,
      visualInspectionId: visualInspectionId,
      evidenceRequirements: [
        for (final category in [
          'montaje general',
          'banco de pruebas',
          'instrumentos',
          'estado final',
        ])
          EvidenceRequirement(id: const Uuid().v4(), category: category),
      ],
    );
    await save(value);
    await index.put(indexKey(hydrant.id), value.id);
    return value;
  }

  Future<FunctionalInspection> createRepeat(
    Hydrant hydrant,
    AppUser user,
    FunctionalInspection previous,
  ) async {
    if (hasActive(hydrant.id)) {
      throw StateError(
        'Ya existe un REPORTE FUNCIONAL activo para el hidrante.',
      );
    }
    final now = DateTime.now().toUtc();
    final value = FunctionalInspection(
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
      updatedAt: now,
      repeatOfInspectionId: previous.id,
      visualInspectionId: previous.visualInspectionId,
      evidenceRequirements: [
        for (final category in [
          'montaje general',
          'banco de pruebas',
          'instrumentos',
          'estado final',
        ])
          EvidenceRequirement(id: const Uuid().v4(), category: category),
      ],
    );
    await save(value);
    await index.put(indexKey(hydrant.id), value.id);
    return value;
  }

  Future<void> save(FunctionalInspection value) async {
    final encoded = VersionedJsonCodec.encode(
      schemaVersion: value.schemaVersion,
      payload: value.toJson(),
    );
    final old = documents.get(value.id);
    if (old != null) {
      final stored = FunctionalInspection.fromJson(
        VersionedJsonCodec.decode(old).payload,
      );
      if (stored.status == FunctionalInspectionStatus.completed ||
          stored.status == FunctionalInspectionStatus.synced) {
        throw StateError(
          'El REPORTE FUNCIONAL finalizado es inmutable. Crea una revisión.',
        );
      }
      if (stored.status != value.status) {
        final transition = const ReportStateMachine().evaluate(
          ReportTransitionRequest(
            reportId: value.id,
            reportType: 'f02B',
            currentState: ReportState.values.byName(stored.status.name),
            requestedState: ReportState.values.byName(value.status.name),
            actor: value.inspectorId,
            role: 'inspector',
            deviceId: value.deviceId,
            reason:
                value.status == FunctionalInspectionStatus.suspended ||
                    value.status == FunctionalInspectionStatus.cancelled
                ? value.suspensionReason
                : '',
            timestamp: DateTime.now().toUtc(),
            correlationId: const Uuid().v4(),
          ),
        );
        if (!transition.allowed) throw StateError(transition.userMessage);
      }
    }
    if (old != null &&
        VersionedJsonCodec.decode(old).schemaVersion != value.schemaVersion) {
      await documents.put(
        '${value.id}:previous:${DateTime.now().toUtc().microsecondsSinceEpoch}',
        old,
      );
    }
    await documents.put(value.id, encoded);
    final confirmed = documents.get(value.id);
    if (confirmed == null) {
      throw StateError(
        'No fue posible confirmar el borrador de REPORTE FUNCIONAL.',
      );
    }
    FunctionalInspection.fromJson(VersionedJsonCodec.decode(confirmed).payload);
  }

  Future<FunctionalInspection> createRevision(
    FunctionalInspection original,
    AppUser supervisor,
    String reason,
  ) async {
    if (original.status != FunctionalInspectionStatus.completed &&
        original.status != FunctionalInspectionStatus.synced) {
      throw StateError('Solo un REPORTE FUNCIONAL cerrado admite revisión.');
    }
    if (!supervisor.role.toLowerCase().contains('supervisor')) {
      throw StateError('La revisión requiere rol supervisor local.');
    }
    if (reason.trim().isEmpty) throw StateError('El motivo es obligatorio.');
    if (hasActive(original.hydrantId)) {
      throw StateError('Ya existe un REPORTE FUNCIONAL activo.');
    }
    final now = DateTime.now().toUtc();
    final json = original.toJson()
      ..['id'] = const Uuid().v4()
      ..['status'] = FunctionalInspectionStatus.draft.name
      ..['currentStep'] = 1
      ..['currentSubstep'] = 1
      ..['completedAt'] = null
      ..['createdAt'] = now.toIso8601String()
      ..['updatedAt'] = now.toIso8601String()
      ..['revisionOfReportId'] = original.revisionOfReportId ?? original.id
      ..['revisionNumber'] = original.revisionNumber + 1
      ..['previousRevisionId'] = original.id
      ..['revisionReason'] = reason.trim()
      ..['activeRevision'] = true
      ..['supervisorReviewRequired'] = true;
    final revision = FunctionalInspection.fromJson(json);
    await save(revision);
    await index.put(indexKey(revision.hydrantId), revision.id);
    return revision;
  }

  Future<void> finalize(FunctionalInspection value) async {
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    var operation = OperationJournalEntry(
      operationId: const Uuid().v4(),
      operationType: JournalOperationType.finalizeFunctionalReport,
      entityIds: [value.id],
      documentWrites: [value.id],
      indexWrites: [indexKey(value.hydrantId)],
      preparedAt: DateTime.now().toUtc(),
      actor: value.inspectorId,
      deviceId: value.deviceId,
      correlationId: value.id,
    );
    await journal.save(operation);
    try {
      await save(value);
      final raw = documents.get(value.id);
      if (raw == null ||
          FunctionalInspection.fromJson(
                VersionedJsonCodec.decode(raw).payload,
              ).status !=
              FunctionalInspectionStatus.completed) {
        throw StateError(
          'No fue posible confirmar la finalización de REPORTE FUNCIONAL.',
        );
      }
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      await index.delete(indexKey(value.hydrantId));
      await journal.save(operation.advance(JournalStatus.committed));
    } on Object catch (error) {
      await journal.save(
        operation.advance(JournalStatus.needsRecovery, error: '$error'),
      );
      rethrow;
    }
  }

  Future<void> deactivate(FunctionalInspection value) async {
    await save(value);
    final activeId = index.get(indexKey(value.hydrantId));
    if (activeId == value.id) {
      await index.delete(indexKey(value.hydrantId));
    }
  }
}

class FunctionalEntityRepository<T> {
  const FunctionalEntityRepository({
    required this.documents,
    required this.fromJson,
    required this.toJson,
    required this.schemaVersion,
  });
  final Box<String> documents;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final int Function(T) schemaVersion;
  T? get(String id) {
    final raw = documents.get(id);
    return raw == null
        ? null
        : fromJson(VersionedJsonCodec.decode(raw).payload);
  }

  Future<void> put(String id, T value) => documents.put(
    id,
    VersionedJsonCodec.encode(
      schemaVersion: schemaVersion(value),
      payload: toJson(value),
    ),
  );
}

class InstrumentRepository {
  const InstrumentRepository(this.documents);
  final Box<String> documents;
  InstrumentRecord? find(String id) {
    final raw = documents.get(id);
    return raw == null
        ? null
        : InstrumentRecord.fromJson(VersionedJsonCodec.decode(raw).payload);
  }

  Future<void> save(InstrumentRecord value) => documents.put(
    value.id,
    VersionedJsonCodec.encode(
      schemaVersion: value.schemaVersion,
      payload: value.toJson(),
    ),
  );
}

class MeasurementSeriesRepository {
  const MeasurementSeriesRepository(this.documents);
  final Box<String> documents;
  MeasurementSeries? find(String id) {
    final raw = documents.get(id);
    return raw == null
        ? null
        : MeasurementSeries.fromJson(VersionedJsonCodec.decode(raw).payload);
  }

  Future<void> save(MeasurementSeries value) => documents.put(
    value.id,
    VersionedJsonCodec.encode(
      schemaVersion: value.schemaVersion,
      payload: value.toJson(),
    ),
  );
}

class FunctionalTestRepository {
  const FunctionalTestRepository({
    required this.tests,
    required this.valves,
    required this.alarms,
  });
  final Box<String> tests, valves, alarms;
  Future<void> save(FunctionalTestRecord value) {
    final target = value is FunctionalValveTest
        ? valves
        : value is AlarmTest
        ? alarms
        : tests;
    return target.put(
      value.id,
      VersionedJsonCodec.encode(
        schemaVersion: value.schemaVersion,
        payload: value.toJson(),
      ),
    );
  }
}

class FunctionalResultRepository {
  const FunctionalResultRepository(this.documents);
  final Box<String> documents;
  FunctionalInspectionResult? find(String inspectionId) {
    final raw = documents.get(inspectionId);
    return raw == null
        ? null
        : FunctionalInspectionResult.fromJson(
            VersionedJsonCodec.decode(raw).payload,
          );
  }

  Future<void> save(
    String inspectionId,
    FunctionalInspectionResult value, {
    int schemaVersion = 1,
  }) => documents.put(
    inspectionId,
    VersionedJsonCodec.encode(
      schemaVersion: schemaVersion,
      payload: value.toJson(),
    ),
  );
}
