import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/data/rv_recovery_coordinator.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;
  late VisualInspectionRepository visual;
  late RvDraftRepository drafts;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    visual = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    drafts = RvDraftRepository(visual);
  });
  tearDown(() => environment.close());

  RvDraft draft(String id, String account, int answers, int photos, {int retry = 0}) {
    final now = DateTime.utc(2026, 8, 1);
    return RvDraft(
      clientInspectionId: id,
      hydrantId: 'hydrant-$account',
      accountNumber: account,
      fieldSessionId: 'jose',
      checklistId: 'legacy-rv',
      checklistVersion: 1,
      checklistSnapshot: const {'id': 'legacy-rv', 'version': 1, 'sections': []},
      createdAt: now,
      updatedAt: now,
      retryCount: retry,
      answers: {
        for (var i = 0; i < answers; i++)
          'q$i': RvAnswer(
            questionId: 'q$i',
            sectionId: 's',
            answerType: 'text',
            value: 'v$i',
            updatedAt: now,
          ),
      },
      photos: {
        if (photos > 0)
          'legacy': [
            for (var i = 0; i < photos; i++)
              RvPhotoReference(
                photoId: '$id-p$i',
                slotCode: 'legacy',
                status: RvPhotoUploadStatus.pending,
              ),
          ],
      },
    );
  }

  Future<void> persist(RvDraft draft, {Map<String, dynamic>? dataScope}) async {
    final now = draft.createdAt;
    final inspection = VisualInspection(
      id: draft.clientInspectionId,
      hydrantId: draft.hydrantId,
      source: HydrantSource.fieldCreated,
      startedAt: now,
      createdAt: now,
      createdBy: 'jose',
      updatedAt: now,
      unknownFields: {
        RvDraftRepository.storageKey: draft.toJson(),
        'dataScope': ?dataScope,
      },
    );
    await Hive.box<String>('visual_inspections_v1').put(
      inspection.id,
      VersionedJsonCodec.encode(schemaVersion: 1, payload: inspection.toJson()),
    );
  }

  RvRecoveryCoordinator coordinator() => RvRecoveryCoordinator(
    visualRepository: visual,
    drafts: drafts,
    recoveryBox: Hive.box<String>('rv_recovery_v1'),
    snapshotBox: Hive.box<String>('rv_recovery_snapshots_v1'),
    indexBox: Hive.box<String>('active_inspection_index_v1'),
    syncQueueBox: Hive.box<String>('sync_queue'),
    photoBox: Hive.box<String>('inspection_photos_v1'),
    mediaQueueBox: Hive.box<String>('media_sync_queue'),
  );

  test('fixture José selects historical evidence and supersedes empty drafts', () async {
    final fixture = [
      draft('446-history', '446', 54, 10),
      draft('446-empty', '446', 0, 0),
      draft('1134-history', '1134', 55, 10, retry: 401),
      draft('1134-empty', '1134', 0, 0),
      draft('486-2-history', '486-2', 55, 10, retry: 450),
      draft('486-2-empty', '486-2', 0, 0),
      draft('367-2-history', '367-2', 50, 10),
      draft('472-2-history', '472-2', 45, 10),
      for (final account in ['1144', '918', '1167', '461', '626'])
        draft('$account-history', account, 1, 0),
    ];
    for (final value in fixture) {
      await persist(value);
    }
    await Hive.box<String>('active_inspection_index_v1').putAll({
      for (var i = 0; i < 12; i++) 'unreadable-$i': 'missing-$i',
    });

    final result = await coordinator().runLocal();

    expect(result.supersededEmptyDrafts, 3);
    expect(result.retryStormsStopped, 2);
    expect(drafts.find('446-empty')?.supersededBy, '446-history');
    expect(drafts.find('1134-history')?.retryCount, 8);
    expect(drafts.find('486-2-history')?.originalAccountNumber, '486-2');
    expect(drafts.find('486-2-history')?.photoCount, 10);
    expect(Hive.box<String>('active_inspection_index_v1').values, contains('446-history'));
    expect(Hive.box<String>('rv_recovery_snapshots_v1'), isNotEmpty);
  });

  test('ten repeated recoveries converge without losing evidence', () async {
    await persist(draft('history', '486-2', 55, 10, retry: 500));
    await persist(draft('empty', '486-2', 0, 0));
    for (var i = 0; i < 10; i++) {
      await coordinator().runLocal();
    }
    expect(drafts.all(), hasLength(2));
    expect(drafts.find('history')?.answers, hasLength(55));
    expect(drafts.find('history')?.photoCount, 10);
    expect(drafts.find('history')?.retryCount, 8);
    expect(drafts.find('empty')?.supersededBy, 'history');
  });

  test('two meaningful drafts are preserved and not auto-merged', () async {
    await persist(draft('a', '352-1', 5, 1));
    await persist(draft('b', '352-1', 6, 1));
    await coordinator().runLocal();
    expect(drafts.all(), hasLength(2));
    expect(drafts.find('a')?.supersededBy, isNull);
    expect(drafts.find('b')?.supersededBy, isNull);
  });

  test('rebuilds owner-scoped index before the session is restored', () async {
    await persist(
      draft('scoped', '446', 54, 10),
      dataScope: const {
        'environment': 'Production',
        'accountId': 'DDR 001',
        'ownerUserId': 'jose',
      },
    );
    await coordinator().runLocal();
    expect(
      Hive.box<String>('active_inspection_index_v1').get(
        'production/ddr%20001/jose/hydrant-446/f02A',
      ),
      'scoped',
    );
  });
}
