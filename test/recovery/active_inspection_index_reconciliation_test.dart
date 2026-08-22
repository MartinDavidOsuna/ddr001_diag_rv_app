import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
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
}
