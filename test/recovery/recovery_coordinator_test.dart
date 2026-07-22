import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/data/local/integrity_audit_service.dart';
import 'package:ddr001diag/data/local/operation_journal_repository.dart';
import 'package:ddr001diag/data/local/quarantine_repository.dart';
import 'package:ddr001diag/data/local/recovery_coordinator.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;
  late OperationJournalRepository journal;
  late RecoveryCoordinator recovery;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    journal = OperationJournalRepository(Hive.box<String>('operation_journal_v1'));
    recovery = RecoveryCoordinator(
      auditService: const IntegrityAuditService(),
      journal: journal,
      quarantine: QuarantineRepository(Hive.box<String>('quarantine_v1')),
    );
  });
  tearDown(() => environment.close());

  OperationJournalEntry entry({
    required String id,
    required JournalStatus status,
    JournalOperationType type = JournalOperationType.createVisualReport,
    List<String> documents = const [],
    List<String> queues = const [],
  }) => OperationJournalEntry(
    operationId: id,
    operationType: type,
    documentWrites: documents,
    queueWrites: queues,
    status: status,
    preparedAt: DateTime.utc(2026, 7, 15),
    actor: 'actor',
    deviceId: 'device',
    correlationId: id,
  );

  test('prepared vacío se compensa sin inventar documentos', () async {
    await journal.save(entry(id: 'op-empty', status: JournalStatus.prepared));

    final outcome = await recovery.recoverJournalEntry(journal.find('op-empty')!);

    expect(outcome, JournalRecoveryOutcome.safelyCompensated);
    expect(journal.find('op-empty')?.status, JournalStatus.failed);
    expect(Hive.box<String>('visual_inspections_v1'), isEmpty);
  });

  test('documentsWritten repara índice inequívoco y confirma', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-1',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {'id': 'rv-1', 'hydrantId': 'h-1', 'status': 'inProgress'},
      ),
    );
    await journal.save(
      entry(
        id: 'op-rv',
        status: JournalStatus.documentsWritten,
        documents: const ['rv-1'],
      ),
    );

    final outcome = await recovery.recoverJournalEntry(journal.find('op-rv')!);

    expect(outcome, JournalRecoveryOutcome.committed);
    expect(Hive.box<String>('active_inspection_index_v1').get('h-1:f02A'), 'rv-1');
    expect(journal.find('op-rv')?.status, JournalStatus.committed);
  });

  test('queueWritten incompleto queda recuperable y conserva evidencia', () async {
    final source = entry(
      id: 'op-partial',
      status: JournalStatus.queueWritten,
      documents: const ['missing-report'],
      queues: const ['missing-queue'],
    );
    await journal.save(source);

    final outcome = await recovery.recoverJournalEntry(source);

    expect(outcome, JournalRecoveryOutcome.manualReview);
    expect(journal.find(source.operationId)?.status, JournalStatus.needsRecovery);
    expect(journal.find(source.operationId)?.lastError, contains('queueWritten'));
  });

  test('auditor detecta índice huérfano y recuperación lo retira', () async {
    await Hive.box<String>('active_inspection_index_v1').put('h-1:f02A', 'missing');

    final summary = await recovery.runLightweight();

    expect(summary.audit.issues.any((issue) => issue.entityId == 'missing'), isTrue);
    expect(Hive.box<String>('active_inspection_index_v1').containsKey('h-1:f02A'), isFalse);
    expect(summary.repaired, greaterThanOrEqualTo(1));
  });
}
