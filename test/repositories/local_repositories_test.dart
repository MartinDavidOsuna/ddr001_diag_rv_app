import 'package:ddr001diag/data/local/operation_journal_repository.dart';
import 'package:ddr001diag/data/local/quarantine_repository.dart';
import 'package:ddr001diag/data/local/sync_queue_repository.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/sync/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
  });
  tearDown(() => environment.close());

  test('journal persiste, reabre y omite JSON ilegible sin borrarlo', () async {
    final box = Hive.box<String>('operation_journal_v1');
    final repository = OperationJournalRepository(box);
    final entry = OperationJournalEntry(
      operationId: 'op-1',
      operationType: JournalOperationType.createHydrant,
      status: JournalStatus.documentsWritten,
      preparedAt: DateTime.utc(2026, 7, 15),
      actor: 'actor',
      deviceId: 'device',
      correlationId: 'corr',
    );
    await repository.save(entry);
    await box.put('corrupt', '{not-json');

    await box.close();
    final reopened = await Hive.openBox<String>('operation_journal_v1');
    final restoredRepository = OperationJournalRepository(reopened);
    expect(
      restoredRepository.find('op-1')?.status,
      JournalStatus.documentsWritten,
    );
    expect(
      restoredRepository.pending().map((value) => value.operationId),
      ['op-1'],
    );
    expect(reopened.get('corrupt'), '{not-json');
  });

  test('cuarentena conserva íntegramente el documento y hash estable', () async {
    final repository = QuarantineRepository(Hive.box<String>('quarantine_v1'));
    const original = '{"token":"no-se-elimina","broken":';
    final first = await repository.preserve(
      sourceBox: 'visual_inspections_v1',
      sourceKey: 'rv-bad',
      originalDocument: original,
      errorType: 'corruptJson',
      technicalMessage: 'JSON truncado',
    );
    final second = await repository.preserve(
      sourceBox: 'visual_inspections_v1',
      sourceKey: 'rv-bad-2',
      originalDocument: original,
      errorType: 'corruptJson',
      technicalMessage: 'JSON truncado',
    );

    expect(first.originalDocument, original);
    expect(first.contentHash, second.contentHash);
    expect(Hive.box<String>('quarantine_v1').length, 2);
  });

  test('cola respeta dependencias y no considera ilegibles sincronizados', () async {
    final box = Hive.box<String>('sync_queue');
    final repository = SyncQueueRepository(box);
    final now = DateTime.utc(2026, 7, 15);
    SyncQueueItem item(
      String id,
      SyncQueueStatus status, {
      List<String> dependencies = const [],
    }) => SyncQueueItem(
      id: id,
      entityType: 'test',
      entityId: id,
      dependencyIds: dependencies,
      status: status,
      createdAt: now,
      updatedAt: now,
    );

    await repository.save(item('hydrant', SyncQueueStatus.synced));
    await repository.save(
      item('report', SyncQueueStatus.pending, dependencies: ['hydrant']),
    );
    await repository.save(
      item('photo', SyncQueueStatus.pending, dependencies: ['report']),
    );

    expect(repository.ready().map((value) => value.id), ['report']);
    expect(repository.allSynchronized, isFalse);
    await box.put('bad', 'not json');
    expect(repository.unreadableCount, 1);
    expect(box.containsKey('bad'), isTrue);
  });
}
