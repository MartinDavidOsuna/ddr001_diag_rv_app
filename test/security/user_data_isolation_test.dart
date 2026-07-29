import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/data/local/sync_queue_repository.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/domain/sync/sync_queue_item.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment hive;
  late VisualInspectionRepository inspections;
  late SyncQueueRepository queue;

  const userA = AppUser(
    id: 'user-a',
    fullName: 'Usuario A',
    email: 'a@example.invalid',
    role: 'field',
    brigadeId: 'crew-a',
    brigadeName: 'Crew A',
    deviceId: 'device',
  );
  const hydrant = Hydrant(
    id: 'hydrant',
    code: 'TEST-12-5-3-NORMAL',
    locality: 'Test',
    parcel: 'Test',
    priority: PriorityLevel.medium,
    access: AccessType.vehicle,
    syncStatus: SyncStatus.local,
    f02a: InspectionSummary(
      type: InspectionType.f02A,
      status: InspectionStatus.pending,
      progress: 0,
    ),
    f02b: InspectionSummary(
      type: InspectionType.f02B,
      status: InspectionStatus.pending,
      progress: 0,
    ),
    latitude: 29,
    longitude: -110,
  );

  LocalDataScope scope(String user, String crew, {String env = 'test'}) =>
      LocalDataScope(
        environment: env,
        accountId: 'rv-field',
        userId: user,
        brigadeId: crew,
        role: 'field',
      );

  setUp(() async {
    hive = HiveTestEnvironment();
    await hive.open();
    inspections = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    queue = SyncQueueRepository(Hive.box<String>('sync_queue'));
  });

  tearDown(() => hive.close());

  test('usuario B no ve ni abre el borrador de A; A lo conserva', () async {
    inspections.setAccessScope(scope('user-a', 'crew-a'));
    final draftA = await inspections.openOrCreate(hydrant, userA);
    expect(inspections.findById(draftA.id), isNotNull);

    inspections.setAccessScope(scope('user-b', 'crew-b'));
    expect(inspections.accessible(), isEmpty);
    expect(inspections.findById(draftA.id), isNull);
    expect(inspections.hasLocalInspection(hydrant.id), isFalse);

    inspections.setAccessScope(scope('user-a', 'crew-a'));
    expect(inspections.findById(draftA.id)?.createdBy, 'user-a');
  });

  test('cambio de ambiente no mezcla documentos', () async {
    inspections.setAccessScope(scope('user-a', 'crew-a', env: 'test'));
    final draft = await inspections.openOrCreate(hydrant, userA);

    inspections.setAccessScope(scope('user-a', 'crew-a', env: 'staging'));
    expect(inspections.findById(draft.id), isNull);
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).keys.where((key) => '$key'.contains('staging')).isEmpty,
      isTrue,
    );
  });

  test('cola offline de A no queda lista ni visible bajo B', () async {
    queue.setAccessScope(scope('user-a', 'crew-a'));
    final now = DateTime.utc(2026, 7, 27);
    await queue.save(
      SyncQueueItem(
        id: 'answer:a',
        entityType: 'answer',
        entityId: 'a',
        ownerUserId: 'user-a',
        accountId: 'rv-field',
        environment: 'test',
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(queue.ready(), hasLength(1));

    queue.setAccessScope(scope('user-b', 'crew-b'));
    expect(queue.all(), isEmpty);
    expect(queue.ready(), isEmpty);
    expect(Hive.box<String>('sync_queue').containsKey('answer:a'), isTrue);

    queue.setAccessScope(scope('user-a', 'crew-a'));
    expect(queue.ready(), hasLength(1));
  });

  test('cola heredada sin propietario queda restringida', () async {
    final now = DateTime.utc(2026, 7, 27);
    await queue.save(
      SyncQueueItem(
        id: 'legacy',
        entityType: 'answer',
        entityId: 'legacy',
        createdAt: now,
        updatedAt: now,
      ),
    );
    queue.setAccessScope(scope('user-a', 'crew-a'));
    expect(queue.all(), isEmpty);
    expect(Hive.box<String>('sync_queue').containsKey('legacy'), isTrue);
  });
}
