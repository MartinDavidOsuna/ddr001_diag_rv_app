import 'dart:convert';

import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/core/security/local_data_scope.dart';
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

  RvDraft draft(
    String id,
    String account,
    int answers,
    int photos, {
    int retry = 0,
    RvLocalStatus status = RvLocalStatus.pendingCreate,
  }) {
    final now = DateTime.utc(2026, 8, 1);
    return RvDraft(
      clientInspectionId: id,
      hydrantId: 'hydrant-$account',
      accountNumber: account,
      fieldSessionId: 'jose',
      checklistId: 'legacy-rv',
      checklistVersion: 1,
      checklistSnapshot: const {
        'id': 'legacy-rv',
        'version': 1,
        'sections': [],
      },
      createdAt: now,
      updatedAt: now,
      retryCount: retry,
      localStatus: status,
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

  Future<void> persist(
    RvDraft draft, {
    Map<String, dynamic>? dataScope,
    String? archiveState,
    String createdBy = 'jose',
    String inspectorId = '',
  }) async {
    final now = draft.createdAt;
    final inspection = VisualInspection(
      id: draft.clientInspectionId,
      hydrantId: draft.hydrantId,
      source: HydrantSource.fieldCreated,
      startedAt: now,
      createdAt: now,
      createdBy: createdBy,
      inspectorId: inspectorId,
      updatedAt: now,
      unknownFields: {
        RvDraftRepository.storageKey: draft.toJson(),
        'dataScope': ?dataScope,
        'archiveState': ?archiveState,
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

  Future<List<BoxEvent>> writesDuring(
    Box<String> box,
    Future<void> Function() action,
  ) async {
    final events = <BoxEvent>[];
    final subscription = box.watch().listen(events.add);
    await action();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return events;
  }

  test(
    '27 documents preserve all evidence and index only 5 editable drafts',
    () async {
      for (var i = 0; i < 27; i++) {
        final terminal = i < 22;
        final value = draft(
          'inspection-$i',
          '${1000 + i}',
          40,
          9,
          status: terminal
              ? RvLocalStatus.submitted
              : RvLocalStatus.pendingPhotos,
        );
        await persist(value);
        await Hive.box<String>(
          'active_inspection_index_v1',
        ).put('${value.hydrantId}:f02A', value.clientInspectionId);
      }
      await coordinator().runLocal();
      expect(Hive.box<String>('visual_inspections_v1'), hasLength(27));
      expect(drafts.all(), hasLength(27));
      expect(drafts.all().fold<int>(0, (n, d) => n + d.answers.length), 1080);
      expect(drafts.all().fold<int>(0, (n, d) => n + d.photoCount), 243);
      expect(Hive.box<String>('active_inspection_index_v1'), hasLength(5));
    },
  );

  test(
    'fixture José selects historical evidence and supersedes empty drafts',
    () async {
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
      await Hive.box<String>(
        'active_inspection_index_v1',
      ).putAll({for (var i = 0; i < 12; i++) 'unreadable-$i': 'missing-$i'});

      final result = await coordinator().runLocal();

      expect(result.supersededEmptyDrafts, 3);
      expect(result.retryStormsStopped, 2);
      expect(drafts.find('446-empty')?.supersededBy, '446-history');
      expect(drafts.find('1134-history')?.retryCount, 8);
      expect(drafts.find('486-2-history')?.originalAccountNumber, '486-2');
      expect(drafts.find('486-2-history')?.photoCount, 10);
      expect(
        Hive.box<String>('active_inspection_index_v1').values,
        contains('446-history'),
      );
      expect(Hive.box<String>('rv_recovery_snapshots_v1'), isNotEmpty);
    },
  );

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

  test(
    'segundo recovery equivalente hace cero escrituras y conserva timestamps',
    () async {
      final value = draft('2392-fixture', '2392', 53, 10, retry: 9);
      await persist(value);
      await coordinator().runLocal();
      final recovered = drafts.find(value.clientInspectionId)!;
      final documentBefore = Hive.box<String>(
        'visual_inspections_v1',
      ).get(value.clientInspectionId);
      final recoveryBefore = Hive.box<String>('rv_recovery_v1').get('current');
      final snapshotsBefore = Map<Object, String>.from(
        Hive.box<String>('rv_recovery_snapshots_v1').toMap(),
      );

      late List<BoxEvent> recoveryWrites;
      late List<BoxEvent> snapshotWrites;
      late List<BoxEvent> indexWrites;
      final documentWrites = await writesDuring(
        Hive.box<String>('visual_inspections_v1'),
        () async {
          recoveryWrites = await writesDuring(
            Hive.box<String>('rv_recovery_v1'),
            () async {
              snapshotWrites = await writesDuring(
                Hive.box<String>('rv_recovery_snapshots_v1'),
                () async {
                  indexWrites = await writesDuring(
                    Hive.box<String>('active_inspection_index_v1'),
                    coordinator().runLocal,
                  );
                },
              );
            },
          );
        },
      );

      expect(documentWrites, isEmpty);
      expect(recoveryWrites, isEmpty);
      expect(snapshotWrites, isEmpty);
      expect(indexWrites, isEmpty);
      expect(
        Hive.box<String>('visual_inspections_v1').get(value.clientInspectionId),
        documentBefore,
      );
      expect(
        drafts.find(value.clientInspectionId)!.updatedAt,
        recovered.updatedAt,
      );
      expect(Hive.box<String>('rv_recovery_v1').get('current'), recoveryBefore);
      expect(
        Hive.box<String>('rv_recovery_snapshots_v1').toMap(),
        snapshotsBefore,
      );
    },
  );

  test('recovery running se reanuda sin crear otro snapshot', () async {
    final value = draft('resume-fixture', '8008', 2, 1);
    await persist(value);
    await Hive.box<String>(
      'active_inspection_index_v1',
    ).put('${value.hydrantId}:f02A', value.clientInspectionId);
    await Hive.box<String>('rv_recovery_v1').put(
      'current',
      '{"runId":"resume-run","status":"running",'
          '"startedAt":"2026-08-01T00:00:00.000Z"}',
    );
    await Hive.box<String>(
      'rv_recovery_snapshots_v1',
    ).put('resume-run', '{"preserved":true}');

    final result = await coordinator().runLocal();

    expect(result.runId, 'resume-run');
    expect(Hive.box<String>('rv_recovery_snapshots_v1'), hasLength(1));
    expect(
      Hive.box<String>('rv_recovery_snapshots_v1').get('resume-run'),
      '{"preserved":true}',
    );
    expect(
      (jsonDecode(Hive.box<String>('rv_recovery_v1').get('current')!)
          as Map)['status'],
      'completed',
    );
  });

  test('completed legacy sin fingerprint crea una sola línea base', () async {
    final value = draft('legacy-fingerprint', '7979', 1, 0);
    await persist(value);
    await Hive.box<String>(
      'active_inspection_index_v1',
    ).put('${value.hydrantId}:f02A', value.clientInspectionId);
    await Hive.box<String>(
      'rv_recovery_v1',
    ).put('current', '{"runId":"legacy-completed","status":"completed"}');
    final snapshots = Hive.box<String>('rv_recovery_snapshots_v1');

    await coordinator().runLocal();
    expect(snapshots, hasLength(1));
    final current = Map<String, dynamic>.from(
      jsonDecode(Hive.box<String>('rv_recovery_v1').get('current')!) as Map,
    );
    expect(current['stateFingerprint'], isNotEmpty);
    final once = Map<Object, String>.from(snapshots.toMap());

    await coordinator().runLocal();
    expect(snapshots.toMap(), once);
  });

  test('dos invocaciones concurrentes crean un solo snapshot', () async {
    final value = draft('concurrent-fixture', '8080', 3, 1, retry: 9);
    await persist(value);
    final snapshots = Hive.box<String>('rv_recovery_snapshots_v1');
    final events = <BoxEvent>[];
    final subscription = snapshots.watch().listen(events.add);

    final results = await Future.wait([
      coordinator().runLocal(),
      coordinator().runLocal(),
    ]);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(results.map((result) => result.documents), everyElement(1));
    expect(snapshots, hasLength(1));
    expect(events, hasLength(1));
    expect(drafts.find(value.clientInspectionId)?.retryCount, 8);
  });

  test('misma cantidad con identidad distinta crea trabajo nuevo', () async {
    final first = draft('identity-a', '8181', 2, 1);
    await persist(first);
    await coordinator().runLocal();
    final snapshots = Hive.box<String>('rv_recovery_snapshots_v1');
    expect(snapshots, hasLength(1));

    await Hive.box<String>(
      'visual_inspections_v1',
    ).delete(first.clientInspectionId);
    final second = draft('identity-b', '8181', 2, 1);
    await persist(second);
    await coordinator().runLocal();

    expect(Hive.box<String>('visual_inspections_v1'), hasLength(1));
    expect(snapshots, hasLength(2));
    expect(
      Hive.box<String>('active_inspection_index_v1').values,
      contains(second.clientInspectionId),
    );
  });

  test('cambio de scope no reutiliza fingerprint completado', () async {
    final value = draft('scope-fingerprint', '8282', 1, 0);
    await persist(
      value,
      dataScope: const {
        'environment': 'production',
        'accountId': 'account-a',
        'ownerUserId': 'jose',
      },
    );
    await coordinator().runLocal();
    final snapshots = Hive.box<String>('rv_recovery_snapshots_v1');
    expect(snapshots, hasLength(1));

    await persist(
      value,
      dataScope: const {
        'environment': 'production',
        'accountId': 'account-b',
        'ownerUserId': 'jose',
      },
    );
    await coordinator().runLocal();

    expect(snapshots, hasLength(2));
    expect(
      Hive.box<String>('active_inspection_index_v1').keys.single,
      contains('account-b'),
    );
  });

  test('recovery scoped no elimina índice de otra cuenta', () async {
    final owned = draft('scope-owned', '8383', 1, 0);
    final foreign = draft('scope-foreign', '8484', 1, 0);
    await persist(
      owned,
      dataScope: const {
        'environment': 'production',
        'accountId': 'account-a',
        'ownerUserId': 'jose',
      },
    );
    await persist(
      foreign,
      dataScope: const {
        'environment': 'production',
        'accountId': 'account-b',
        'ownerUserId': 'jose',
      },
    );
    const ownedKey = 'production/account-a/jose/hydrant-8383/f02A';
    const foreignKey = 'production/account-b/jose/hydrant-8484/f02A';
    await Hive.box<String>('active_inspection_index_v1').putAll({
      ownedKey: owned.clientInspectionId,
      foreignKey: foreign.clientInspectionId,
    });
    visual.setAccessScope(
      const LocalDataScope(
        environment: 'production',
        accountId: 'account-a',
        userId: 'jose',
        brigadeId: 'qa-brigade',
        role: 'technician',
      ),
    );

    await coordinator().runLocal();

    expect(
      Hive.box<String>('active_inspection_index_v1').get(ownedKey),
      owned.clientInspectionId,
    );
    expect(
      Hive.box<String>('active_inspection_index_v1').get(foreignKey),
      foreign.clientInspectionId,
    );
  });

  test('two meaningful drafts are preserved and not auto-merged', () async {
    await persist(draft('a', '352-1', 5, 1));
    await persist(draft('b', '352-1', 6, 1));
    await coordinator().runLocal();
    expect(drafts.all(), hasLength(2));
    expect(drafts.find('a')?.supersededBy, isNull);
    expect(drafts.find('b')?.supersededBy, isNull);
  });

  test(
    'cancelled and archived reviews remain documents but not active',
    () async {
      await persist(
        draft('cancelled', '8001', 2, 1, status: RvLocalStatus.cancelled),
      );
      await persist(draft('archived', '8002', 2, 1), archiveState: 'archived');

      await coordinator().runLocal();

      expect(drafts.all(), hasLength(2));
      expect(Hive.box<String>('active_inspection_index_v1'), isEmpty);
    },
  );

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
      Hive.box<String>(
        'active_inspection_index_v1',
      ).get('production/ddr%20001/jose/hydrant-446/f02A'),
      'scoped',
    );
  });

  test(
    'upgrade 108 canonicaliza owner/hydrant y converge con cero escrituras',
    () async {
      final value = draft('upgrade-108', 'A+B/01', 4, 2);
      await persist(
        value,
        createdBy: ' CREATED-1 ',
        inspectorId: 'INSPECTOR-1',
        dataScope: const {
          'environment': ' Production ',
          'accountId': ' DDR 001 ',
          'ownerUserId': '   ',
        },
      );
      final index = Hive.box<String>('active_inspection_index_v1');
      final legacyKey = '${value.hydrantId}:f02A';
      const scopedKey =
          'production/ddr%20001/created-1/hydrant-a%2Bb%2F01/f02A';
      await index.put(legacyKey, value.clientInspectionId);
      final observed = [
        Hive.box<String>('visual_inspections_v1'),
        index,
        Hive.box<String>('rv_recovery_v1'),
        Hive.box<String>('rv_recovery_snapshots_v1'),
        Hive.box<String>('sync_queue'),
        Hive.box<String>('inspection_photos_v1'),
        Hive.box<String>('media_sync_queue'),
      ];

      Future<List<BoxEvent>> runAndCollect() async {
        final events = <BoxEvent>[];
        final subscriptions = [
          for (final box in observed) box.watch().listen(events.add),
        ];
        await coordinator().runLocal();
        await Future<void>.delayed(Duration.zero);
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        return events;
      }

      final first = await runAndCollect();
      final firstFingerprint = jsonDecode(
        Hive.box<String>('rv_recovery_v1').get('current')!,
      )['stateFingerprint'];
      final second = await runAndCollect();
      final secondFingerprint = jsonDecode(
        Hive.box<String>('rv_recovery_v1').get('current')!,
      )['stateFingerprint'];
      final third = await runAndCollect();
      final thirdFingerprint = jsonDecode(
        Hive.box<String>('rv_recovery_v1').get('current')!,
      )['stateFingerprint'];

      expect(first, isNotEmpty);
      expect(index.get(scopedKey), value.clientInspectionId);
      expect(index.containsKey(legacyKey), isFalse);
      expect(second, isEmpty);
      expect(third, isEmpty);
      expect(secondFingerprint, firstFingerprint);
      expect(thirdFingerprint, secondFingerprint);
      final recovered = drafts.find(value.clientInspectionId)!;
      expect(
        recovered.answers.map((key, answer) => MapEntry(key, answer.toJson())),
        value.answers.map((key, answer) => MapEntry(key, answer.toJson())),
      );
      expect(
        recovered.photos.map(
          (key, photos) => MapEntry(
            key,
            photos.map((photo) => photo.toJson()).toList(growable: false),
          ),
        ),
        value.photos.map(
          (key, photos) => MapEntry(
            key,
            photos.map((photo) => photo.toJson()).toList(growable: false),
          ),
        ),
      );
    },
  );
}
