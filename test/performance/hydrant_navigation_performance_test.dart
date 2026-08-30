import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HiveTestEnvironment environment;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
  });

  tearDown(() => environment.close());

  test(
    'reabrir un reporte activo usa el índice sin recorrer el archivo',
    () async {
      final visual = _CountingVisualRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      );
      final drafts = RvDraftRepository(visual);
      final first = await drafts.openOrCreate(
        hydrant: _hydrant,
        user: _user,
        checklist: _checklist,
      );
      visual.accessibleCalls = 0;

      final reopened = await drafts.openOrCreate(
        hydrant: _hydrant,
        user: _user,
        checklist: _checklist,
      );

      expect(reopened.clientInspectionId, first.clientInspectionId);
      expect(
        drafts.find(first.clientInspectionId)?.clientInspectionId,
        reopened.clientInspectionId,
        reason:
            'historial y ruta por hidrante deben resolver el mismo documento',
      );
      expect(
        visual.accessibleCalls,
        0,
        reason: 'la ruta normal debe decodificar sólo el documento indexado',
      );
    },
  );

  test('la ruta indexada conserva el scope de acceso local', () async {
    final visual = _CountingVisualRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    final drafts = RvDraftRepository(visual);
    await drafts.openOrCreate(
      hydrant: _hydrant,
      user: _user,
      checklist: _checklist,
    );
    visual.setAccessScope(
      const LocalDataScope(
        environment: 'test',
        accountId: 'rv-field',
        userId: 'different-user',
        brigadeId: 'different-brigade',
        role: 'field',
      ),
    );

    expect(drafts.activeFor(_hydrant.id), isNull);
    expect(visual.forHydrant(_hydrant.id), isEmpty);
  });

  test('índice corrupto no bloquea la recuperación por cuenta', () async {
    final visual = _CountingVisualRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    final drafts = RvDraftRepository(visual);
    final existing = await drafts.openOrCreate(
      hydrant: _hydrant,
      user: _user,
      checklist: _checklist,
    );
    await visual.index.put('${_hydrant.id}:f02A', 'corrupt-target');
    await visual.documents.put('corrupt-target', '{not-json');

    final recovered = await drafts.openOrCreate(
      hydrant: _hydrant,
      user: _user,
      checklist: _checklist,
    );

    expect(recovered.clientInspectionId, existing.clientInspectionId);
    expect(visual.documents.containsKey('corrupt-target'), isTrue);
  });

  test(
    'fallback legacy conserva identidad con UUID en distinto casing',
    () async {
      final visual = _CountingVisualRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      );
      final drafts = RvDraftRepository(visual);
      final existing = await drafts.openOrCreate(
        hydrant: _hydrant,
        user: _user,
        checklist: _checklist,
      );
      final stored = visual.findById(existing.clientInspectionId)!;
      await visual.index.delete('${_hydrant.id}:f02A');
      final upperHydrant = _hydrantWithId(_hydrant.id.toUpperCase());
      await visual.documents.put(
        stored.id,
        VersionedJsonCodec.encode(
          schemaVersion: stored.schemaVersion,
          payload: stored.toJson(),
        ),
      );

      final recovered = await drafts.openOrCreate(
        hydrant: upperHydrant,
        user: _user,
        checklist: _checklist,
      );

      expect(recovered.clientInspectionId, existing.clientInspectionId);
    },
  );
}

class _CountingVisualRepository extends VisualInspectionRepository {
  _CountingVisualRepository({required super.documents, required super.index});

  int accessibleCalls = 0;

  @override
  List<VisualInspection> accessible() {
    accessibleCalls++;
    return super.accessible();
  }
}

const _user = AppUser(
  id: 'synthetic-user',
  fullName: 'Técnico QA',
  email: 'qa@example.test',
  role: 'inspector',
  brigadeId: 'synthetic-brigade',
  brigadeName: 'QA',
  deviceId: 'synthetic-device',
);

const _hydrant = Hydrant(
  id: 'synthetic-hydrant',
  code: 'QA-2392',
  locality: '',
  parcel: '',
  priority: PriorityLevel.medium,
  access: AccessType.vehicle,
  syncStatus: SyncStatus.synced,
  f02a: InspectionSummary(
    type: InspectionType.f02A,
    status: InspectionStatus.inProgress,
    progress: 0.5,
  ),
  f02b: InspectionSummary(
    type: InspectionType.f02B,
    status: InspectionStatus.notRequired,
    progress: 0,
  ),
  latitude: 0,
  longitude: 0,
);

final _checklist = DynamicChecklist(
  id: 'synthetic-checklist',
  code: 'RV',
  version: 2,
  title: 'RV sintético',
  etag: 'synthetic',
  cachedAt: DateTime.utc(2026, 8, 28),
  sections: const [],
);

Hydrant _hydrantWithId(String id) => Hydrant(
  id: id,
  code: _hydrant.code,
  locality: _hydrant.locality,
  parcel: _hydrant.parcel,
  priority: _hydrant.priority,
  access: _hydrant.access,
  syncStatus: _hydrant.syncStatus,
  f02a: _hydrant.f02a,
  f02b: _hydrant.f02b,
  latitude: _hydrant.latitude,
  longitude: _hydrant.longitude,
);
