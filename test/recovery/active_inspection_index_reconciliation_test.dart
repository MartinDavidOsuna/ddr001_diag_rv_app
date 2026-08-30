import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late Box<String> documents;
  late Box<String> index;
  late HiveTestEnvironment environment;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    documents = Hive.box<String>('visual_inspections_v1');
    index = Hive.box<String>('active_inspection_index_v1');
  });

  tearDown(() => environment.close());

  test(
    'second launch removes stale completed and missing index entries',
    () async {
      final now = DateTime.utc(2026, 8, 14);
      final completed = VisualInspection(
        id: 'inspection-completed',
        hydrantId: 'hydrant-1',
        source: HydrantSource.fieldCreated,
        inspectorId: 'user-1',
        inspectorName: 'Field User',
        brigadeId: 'crew-1',
        brigadeName: 'Crew',
        deviceId: 'device-1',
        status: InspectionStatus.completed,
        startedAt: now,
        completedAt: now,
        createdAt: now,
        createdBy: 'user-1',
        updatedAt: now,
        updatedBy: 'user-1',
      );
      await documents.put(
        completed.id,
        VersionedJsonCodec.encode(
          schemaVersion: completed.schemaVersion,
          payload: completed.toJson(),
        ),
      );
      await index.put('hydrant-1:f02A', completed.id);
      await index.put('missing:f02A', 'missing-document');
      final repository = VisualInspectionRepository(
        documents: documents,
        index: index,
      );

      expect(await repository.reconcileActiveIndex(), 2);
      expect(await repository.reconcileActiveIndex(), 0);
      expect(documents.containsKey(completed.id), isTrue);
      expect(index, isEmpty);
    },
  );

  test('reconciliación scoped conserva índices de otro usuario', () async {
    const scopeA = LocalDataScope(
      environment: 'production',
      accountId: 'field',
      userId: 'user-a',
      brigadeId: 'crew-a',
      role: 'field',
    );
    const scopeB = LocalDataScope(
      environment: 'production',
      accountId: 'field',
      userId: 'user-b',
      brigadeId: 'crew-b',
      role: 'field',
    );
    final now = DateTime.utc(2026, 8, 29);

    VisualInspection inspection(String id, String user) => VisualInspection(
      id: id,
      hydrantId: 'shared-hydrant',
      source: HydrantSource.fieldCreated,
      inspectorId: user,
      inspectorName: 'Synthetic $user',
      brigadeId: 'crew-$user',
      brigadeName: 'Synthetic',
      deviceId: 'device-$user',
      startedAt: now,
      createdAt: now,
      createdBy: user,
      updatedAt: now,
      updatedBy: user,
      unknownFields: {
        'dataScope': {
          'environment': 'production',
          'accountId': 'field',
          'ownerUserId': user,
        },
      },
    );

    for (final value in [
      inspection('inspection-a', 'user-a'),
      inspection('inspection-b', 'user-b'),
    ]) {
      await documents.put(
        value.id,
        VersionedJsonCodec.encode(
          schemaVersion: value.schemaVersion,
          payload: value.toJson(),
        ),
      );
    }
    final keyA = '${scopeA.namespace}/shared-hydrant/f02A';
    final keyB = '${scopeB.namespace}/shared-hydrant/f02A';
    await index.putAll({keyA: 'inspection-a', keyB: 'inspection-b'});
    final repository = VisualInspectionRepository(
      documents: documents,
      index: index,
    )..setAccessScope(scopeA);

    expect(repository.activeIndexKeyForHydrant('shared-hydrant'), keyA);
    expect(await repository.reconcileActiveIndex(), 0);
    await index.put('shared-hydrant:f02A', 'inspection-b');
    expect(await repository.reconcileActiveIndex(), 0);
    expect(index.get('shared-hydrant:f02A'), 'inspection-b');
    await index.put('shared-hydrant:f02A', 'inspection-a');
    expect(await repository.reconcileActiveIndex(), 1);
    expect(index.get(keyB), 'inspection-b');

    await repository.replaceActiveVisualIndex({keyA: 'inspection-a'});
    expect(index.get(keyA), 'inspection-a');
    expect(index.get(keyB), 'inspection-b');
  });

  test('índice legacy único no se retira antes de crear scoped', () async {
    const scope = LocalDataScope(
      environment: 'qa',
      accountId: 'fixtures',
      userId: 'owner',
      brigadeId: 'crew',
      role: 'field',
    );
    final now = DateTime.utc(2026, 8, 29);
    final value = VisualInspection(
      id: 'legacy-active',
      hydrantId: 'legacy-hydrant',
      source: HydrantSource.fieldCreated,
      inspectorId: 'owner',
      inspectorName: 'Synthetic',
      brigadeId: 'crew',
      brigadeName: 'Synthetic',
      deviceId: 'device',
      startedAt: now,
      createdAt: now,
      createdBy: 'owner',
      updatedAt: now,
      updatedBy: 'owner',
      unknownFields: {
        'dataScope': {
          'environment': 'qa',
          'accountId': 'fixtures',
          'ownerUserId': 'owner',
        },
      },
    );
    await documents.put(
      value.id,
      VersionedJsonCodec.encode(
        schemaVersion: value.schemaVersion,
        payload: value.toJson(),
      ),
    );
    await index.put('legacy-hydrant:f02A', value.id);
    final repository = VisualInspectionRepository(
      documents: documents,
      index: index,
    )..setAccessScope(scope);

    expect(await repository.reconcileActiveIndex(), 0);
    expect(index.get('legacy-hydrant:f02A'), value.id);
  });

  test(
    'repositorio canonicaliza hidrante y escribe scoped antes de legacy',
    () async {
      const scope = LocalDataScope(
        environment: ' Production ',
        accountId: ' DDR 001 ',
        userId: ' OWNER-1 ',
        brigadeId: 'crew',
        role: 'field',
      );
      final repository = VisualInspectionRepository(
        documents: documents,
        index: index,
      )..setAccessScope(scope);
      const legacyKey = ' A+B/01 :f02A';
      const scopedKey = 'production/ddr%20001/owner-1/a%2Bb%2F01/f02A';
      final now = DateTime.utc(2026, 8, 29);
      final inspection = VisualInspection(
        id: 'inspection-1',
        hydrantId: ' A+B/01 ',
        source: HydrantSource.fieldCreated,
        inspectorId: 'OWNER-1',
        startedAt: now,
        createdAt: now,
        createdBy: 'OWNER-1',
        updatedAt: now,
        unknownFields: const {
          'dataScope': {
            'environment': ' Production ',
            'accountId': ' DDR 001 ',
            'ownerUserId': ' OWNER-1 ',
          },
        },
      );
      await documents.put(
        inspection.id,
        VersionedJsonCodec.encode(
          schemaVersion: inspection.schemaVersion,
          payload: inspection.toJson(),
        ),
      );
      await index.put(legacyKey, 'inspection-1');
      final events = <BoxEvent>[];
      final subscription = index.watch().listen(events.add);

      expect(repository.activeIndexKeyForHydrant(' A+B/01 '), scopedKey);
      await repository.replaceActiveVisualIndex(const {
        scopedKey: 'inspection-1',
      });
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(index.get(scopedKey), 'inspection-1');
      expect(index.containsKey(legacyKey), isFalse);
      expect(events.map((event) => event.key), [scopedKey, legacyKey]);
    },
  );
}
