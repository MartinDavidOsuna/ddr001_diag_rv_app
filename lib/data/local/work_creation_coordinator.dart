import 'package:uuid/uuid.dart';

import '../../domain/integrity/operation_journal.dart';
import '../../domain/models/app_models.dart';
import 'functional_repositories.dart';
import 'operation_journal_repository.dart';
import 'visual_inspection_repository.dart';

enum WorkCreationStatus { committed, needsRecovery, failed }

class WorkCreationResult {
  const WorkCreationResult({
    required this.status,
    required this.operationId,
    this.visualReportId,
    this.functionalReportId,
    this.error,
  });
  final WorkCreationStatus status;
  final String operationId;
  final String? visualReportId, functionalReportId, error;
}

class WorkCreationCoordinator {
  const WorkCreationCoordinator({
    required this.visual,
    required this.functional,
    required this.journal,
  });
  final VisualInspectionRepository visual;
  final FunctionalInspectionRepository functional;
  final OperationJournalRepository journal;

  Future<WorkCreationResult> createVisualAndFunctional({
    required Hydrant hydrant,
    required AppUser user,
  }) async {
    final operationId = const Uuid().v4();
    var entry = OperationJournalEntry(
      operationId: operationId,
      operationType: JournalOperationType.createVisualAndFunctional,
      preparedAt: DateTime.now().toUtc(),
      actor: user.id,
      deviceId: user.deviceId,
      correlationId: operationId,
    );
    await journal.save(entry);
    String? visualId, functionalId;
    try {
      final rv = await visual.openOrCreate(hydrant, user);
      visualId = rv.id;
      final rf = await functional.openOrCreate(
        hydrant,
        user,
        visualInspectionId: rv.id,
      );
      functionalId = rf.id;
      entry = OperationJournalEntry(
        operationId: entry.operationId,
        operationType: entry.operationType,
        entityIds: [rv.id, rf.id],
        documentWrites: [rv.id, rf.id],
        indexWrites: ['${hydrant.id}:f02A', '${hydrant.id}:f02B'],
        status: JournalStatus.documentsWritten,
        preparedAt: entry.preparedAt,
        actor: entry.actor,
        deviceId: entry.deviceId,
        correlationId: entry.correlationId,
      );
      await journal.save(entry);
      await journal.save(entry.advance(JournalStatus.committed));
      return WorkCreationResult(
        status: WorkCreationStatus.committed,
        operationId: operationId,
        visualReportId: visualId,
        functionalReportId: functionalId,
      );
    } on Object catch (error) {
      final recoverable = visualId != null || functionalId != null;
      await journal.save(
        entry.advance(
          recoverable ? JournalStatus.needsRecovery : JournalStatus.failed,
          error: '$error',
        ),
      );
      return WorkCreationResult(
        status: recoverable
            ? WorkCreationStatus.needsRecovery
            : WorkCreationStatus.failed,
        operationId: operationId,
        visualReportId: visualId,
        functionalReportId: functionalId,
        error: '$error',
      );
    }
  }
}
