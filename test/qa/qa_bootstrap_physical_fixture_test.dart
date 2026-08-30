import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/core/security/f02a_scoped_identity.dart';
import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/data/local/media_work_item_codec.dart';
import 'package:ddr001diag/data/local/operation_journal_repository.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/qa/qa_bootstrap_lab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  const scope = LocalDataScope(
    environment: 'qa',
    accountId: 'qa-fixtures',
    userId: 'qa-user',
    brigadeId: 'qa-brigade',
    role: 'field',
  );
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'qa-bootstrap-physical-fixture-',
    );
    await _open(root);
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  QaBootstrapLab lab() {
    final visual = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    )..setAccessScope(scope);
    return QaBootstrapLab(
      visualRepository: visual,
      drafts: RvDraftRepository(visual),
      runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
      exportsDirectory: () async => root,
    );
  }

  test(
    'fixture físico equivalente adopta quinta captura y converge con instancias nuevas',
    () async {
      await _seedPhysicalEquivalent(root, scope);
      final seededLab = lab();
      final pendingCapture = (await seededLab.captureDiagnostics()).singleWhere(
        (capture) => capture.value['photoId'] == 'qa-photo-camera-0005',
      );
      expect(pendingCapture.value['journalStatus'], 'queueWritten');
      expect(pendingCapture.value['documentPresent'], isTrue);
      expect(pendingCapture.value['associatedToDraft'], isFalse);
      await seededLab.createLegacyRecoveryWithoutFingerprint();

      final first = await seededLab.run('physical-1');
      await _reopen(root);
      final second = await lab().run('physical-2');
      await _reopen(root);
      final third = await lab().run('physical-3');

      expect(first.totalWrites, 6);
      expect(first.writesByBox['operation_journal_v1'], 1);
      expect(first.writesByBox['visual_inspections_v1'], 1);
      expect(first.writesByBox['rv_recovery_v1'], 2);
      expect(first.writesByBox['rv_recovery_snapshots_v1'], 1);
      expect(first.writesByBox['integrity_audit_reports_v1'], 1);
      expect(first.writesByBox['active_inspection_index_v1'], 0);
      expect(second.totalWrites, 0);
      expect(third.totalWrites, 0);
      expect(second.fingerprintBefore, second.fingerprintAfter);
      expect(third.fingerprintBefore, third.fingerprintAfter);
      expect(second.fingerprintAfter, third.fingerprintBefore);

      final visual = VisualInspectionRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      )..setAccessScope(scope);
      final draft = RvDraftRepository(visual).find('qa-review-camera-0002')!;
      final references = draft.photos.values.expand((items) => items).toList();
      expect(references, hasLength(5));
      expect(
        references.map((reference) => reference.photoId).toSet(),
        hasLength(5),
      );
      final journal = OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      ).find('qa-photo-camera-0005');
      expect(journal?.status, JournalStatus.committed);
      expect(Hive.box<String>('active_inspection_index_v1').keys, [
        '${scope.namespace}/qa-hydrant-camera-0002/f02A',
      ]);
      expect(
        [...first.changes, ...second.changes, ...third.changes].where(
          (change) =>
              change.box == 'active_inspection_index_v1' &&
              change.type != 'insert',
        ),
        isEmpty,
      );
    },
  );

  test(
    'exportar informe es no mutante y omite outputs del fingerprint',
    () async {
      await _seedPhysicalEquivalent(root, scope);
      await lab().createLegacyRecoveryWithoutFingerprint();
      await lab().run('export-source');
      final currentLab = lab();
      final boxes = {
        for (final name in qaObservedBootstrapBoxes)
          name: Hive.box<String>(name),
      };
      final before = {
        for (final entry in boxes.entries)
          entry.key: Map<Object, String>.from(entry.value.toMap()),
      };
      final fingerprintBefore = QaBootstrapLab.functionalFingerprint(
        boxes,
        scopeNamespace: scope.namespace,
      );

      await Hive.box<String>('rv_recovery_snapshots_v1').put(
        'diagnostic-output-only',
        jsonEncode({
          'runId': 'volatile',
          'completedAt': DateTime.utc(2030).toIso8601String(),
        }),
      );
      final outputOnlyFingerprint = QaBootstrapLab.functionalFingerprint(
        boxes,
        scopeNamespace: scope.namespace,
      );
      expect(outputOnlyFingerprint, fingerprintBefore);
      await Hive.box<String>(
        'rv_recovery_snapshots_v1',
      ).delete('diagnostic-output-only');

      final file = await currentLab.exportComparison();
      expect(await file.exists(), isTrue);
      final payload = jsonDecode(await file.readAsString()) as Map;
      expect(payload['productionDataIncluded'], isFalse);
      final captures = (payload['captures'] as List).cast<Map>();
      expect(captures, hasLength(5));
      final recovered = captures.singleWhere(
        (capture) => capture['photoId'] == 'qa-photo-camera-0005',
      );
      expect(recovered['journalMarker'], 'camera-pending-v2');
      expect(recovered['journalVersion'], 2);
      expect(recovered['journalStatus'], 'committed');
      expect(recovered['reviewId'], 'qa-review-camera-0002');
      expect(recovered['slot'], 'no_hydrant_at_location');
      expect(recovered['scopeHash'], hasLength(16));
      expect(recovered['finalPresent'], isTrue);
      expect(recovered['fileSize'], greaterThan(0));
      expect(recovered['fileModifiedAt'], isA<String>());
      expect(recovered['fileModifiedMicros'], greaterThan(0));
      expect(recovered['referenceOrdinal'], 5);
      expect(recovered['physicalSha256'], recovered['normalizedSha256']);
      expect(recovered['workQueueStatus'], isNotNull);
      expect(recovered['documentPresent'], isTrue);
      expect(recovered['workQueuePresent'], isTrue);
      expect(recovered['associatedToDraft'], isTrue);
      expect(recovered['duplicateReferences'], isFalse);
      expect(recovered['stagingCleanAfterCommit'], isTrue);
      final operational = payload['operationalState'] as Map;
      expect(operational['pendingJournalCount'], 0);
      expect(operational['networkEligibleJobCount'], 0);
      expect(operational['recoveryRunningCount'], 0);
      expect(operational['recoveryFailedCount'], 0);
      expect(operational['quarantineCount'], 0);
      expect(operational['scopedIndexKeys'], [
        '${scope.namespace}/qa-hydrant-camera-0002/f02A',
      ]);
      expect(operational['legacyIndexKeys'], isEmpty);
      expect(jsonEncode(payload), isNot(contains(root.path)));
      for (final entry in boxes.entries) {
        expect(entry.value.toMap(), before[entry.key], reason: entry.key);
      }
      expect(
        QaBootstrapLab.functionalFingerprint(
          boxes,
          scopeNamespace: scope.namespace,
        ),
        fingerprintBefore,
      );
    },
  );

  test('upgrade 108 scoped canonical converge en pipeline completo', () async {
    const upgradeScope = LocalDataScope(
      environment: ' Production ',
      accountId: ' DDR 001 ',
      userId: ' CREATED-1 ',
      brigadeId: 'qa-brigade',
      role: 'field',
    );
    const hydrantId = ' QA/HYDRANT +#01 ';
    final expectedKey = buildF02AScopedKey(
      environment: upgradeScope.environment,
      accountId: upgradeScope.accountId,
      ownerUserId: '   ',
      createdBy: ' CREATED-1 ',
      inspectorId: 'INSPECTOR-1',
      hydrantId: hydrantId,
    )!;
    await _seedPhysicalEquivalent(
      root,
      upgradeScope,
      hydrantId: hydrantId,
      ownerUserId: '   ',
      createdBy: ' CREATED-1 ',
      inspectorId: 'INSPECTOR-1',
      legacyIndex: true,
    );

    QaBootstrapLab upgradeLab() {
      final visual = VisualInspectionRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      )..setAccessScope(upgradeScope);
      return QaBootstrapLab(
        visualRepository: visual,
        drafts: RvDraftRepository(visual),
        runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
        exportsDirectory: () async => root,
      );
    }

    await upgradeLab().createLegacyRecoveryWithoutFingerprint();
    final first = await upgradeLab().run('upgrade-108-1');
    await _reopen(root);
    final second = await upgradeLab().run('upgrade-108-2');
    await _reopen(root);
    final third = await upgradeLab().run('upgrade-108-3');

    expect(first.totalWrites, 8);
    expect(first.writesByBox['operation_journal_v1'], 1);
    expect(first.writesByBox['visual_inspections_v1'], 1);
    expect(first.writesByBox['active_inspection_index_v1'], 2);
    expect(first.writesByBox['rv_recovery_v1'], 2);
    expect(first.writesByBox['rv_recovery_snapshots_v1'], 1);
    expect(first.writesByBox['integrity_audit_reports_v1'], 1);
    expect(second.totalWrites, 0);
    expect(third.totalWrites, 0);
    expect(second.fingerprintBefore, second.fingerprintAfter);
    expect(third.fingerprintBefore, third.fingerprintAfter);
    expect(second.fingerprintAfter, third.fingerprintBefore);
    final index = Hive.box<String>('active_inspection_index_v1');
    expect(index.get(expectedKey), 'qa-review-camera-0002');
    expect(index.containsKey('$hydrantId:f02A'), isFalse);
    expect(index.keys, [expectedKey]);
    final draft = RvDraftRepository(
      VisualInspectionRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: index,
      )..setAccessScope(upgradeScope),
    ).find('qa-review-camera-0002')!;
    expect(draft.photoCount, 5);
    expect(
      draft.photos.values
          .expand((references) => references)
          .map((reference) => reference.photoId)
          .toSet(),
      hasLength(5),
    );
    expect(
      OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      ).find('qa-photo-camera-0005')?.status,
      JournalStatus.committed,
    );
    printOnFailure(
      'writes=${first.totalWrites},${second.totalWrites},${third.totalWrites} '
      'fingerprints=${second.fingerprintAfter},${third.fingerprintAfter}',
    );
  });

  test('exportación rota sólo diagnósticos QA antiguos', () async {
    await _seedPhysicalEquivalent(root, scope);
    final currentLab = lab();
    final boxes = {
      for (final name in qaObservedBootstrapBoxes) name: Hive.box<String>(name),
    };
    final before = {
      for (final entry in boxes.entries)
        entry.key: Map<Object, String>.from(entry.value.toMap()),
    };
    final unrelated = File('${root.path}/evidence-do-not-touch.jpg');
    await unrelated.writeAsBytes([1, 2, 3], flush: true);

    for (var index = 0; index < 7; index++) {
      await currentLab.exportComparison();
      await Future<void>.delayed(const Duration(microseconds: 2));
    }

    final exports = root
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (file) => RegExp(
            r'^qa_bootstrap_comparison_[0-9]+\.json$',
          ).hasMatch(file.uri.pathSegments.last),
        )
        .toList();
    expect(exports, hasLength(4));
    expect(unrelated.existsSync(), isTrue);
    for (final entry in boxes.entries) {
      expect(entry.value.toMap(), before[entry.key], reason: entry.key);
    }
  });

  test('fingerprint cambia por identidad funcional, archivo y scope', () async {
    await _seedPhysicalEquivalent(root, scope);
    final boxes = {
      for (final name in qaObservedBootstrapBoxes) name: Hive.box<String>(name),
    };
    final initial = QaBootstrapLab.functionalFingerprint(
      boxes,
      scopeNamespace: scope.namespace,
    );
    final raw = Hive.box<String>(
      'inspection_photos_v1',
    ).get('qa-photo-camera-0001')!;
    await Hive.box<String>(
      'inspection_photos_v1',
    ).delete('qa-photo-camera-0001');
    await Hive.box<String>(
      'inspection_photos_v1',
    ).put('qa-photo-different-id', raw);
    final differentIdentity = QaBootstrapLab.functionalFingerprint(
      boxes,
      scopeNamespace: scope.namespace,
    );
    expect(differentIdentity, isNot(initial));

    await Hive.box<String>(
      'inspection_photos_v1',
    ).delete('qa-photo-different-id');
    await Hive.box<String>(
      'inspection_photos_v1',
    ).put('qa-photo-camera-0001', raw);
    final photo = InspectionPhoto.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    await File(photo.localPath).writeAsBytes([1, 2, 3, 4, 5, 6], flush: true);
    expect(
      QaBootstrapLab.functionalFingerprint(
        boxes,
        scopeNamespace: scope.namespace,
      ),
      isNot(initial),
    );
    expect(
      QaBootstrapLab.functionalFingerprint(
        boxes,
        scopeNamespace: 'qa/another-account/qa-user',
      ),
      isNot(initial),
    );
  });

  test(
    'faltante, cambio físico y journal pendiente reactivan sólo trabajo real',
    () async {
      await _seedPhysicalEquivalent(root, scope);
      final initialLab = lab();
      await initialLab.createLegacyRecoveryWithoutFingerprint();
      await initialLab.run('baseline');
      expect((await initialLab.run('baseline-noop')).totalWrites, 0);

      final photo = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(
                Hive.box<String>(
                  'inspection_photos_v1',
                ).get('qa-photo-camera-0001')!,
              )
              as Map,
        ),
      );
      final file = File(photo.localPath);
      final originalBytes = await file.readAsBytes();
      await file.delete();
      final missing = await initialLab.run('missing-file');
      expect(missing.totalWrites, greaterThan(0));
      final missingNoop = await initialLab.run('missing-file-noop');
      expect(
        missingNoop.totalWrites,
        0,
        reason: jsonEncode(
          missingNoop.changes.map((change) => change.toJson()).toList(),
        ),
      );

      await file.writeAsBytes([...originalBytes, 7], flush: true);
      final physicalChange = await initialLab.run('physical-change');
      printOnFailure(
        'physical-change=${jsonEncode(physicalChange.changes.map((change) => change.toJson()).toList())}',
      );
      expect(physicalChange.totalWrites, greaterThan(0));
      final physicalNoop = await initialLab.run('physical-change-noop');
      expect(
        physicalNoop.totalWrites,
        0,
        reason: jsonEncode(
          physicalNoop.changes.map((change) => change.toJson()).toList(),
        ),
      );

      final pending = OperationJournalEntry(
        operationId: 'qa-pending-camera-safe',
        operationType: JournalOperationType.capturePhoto,
        entityIds: const [
          'camera-pending-v2',
          'qa-review-camera-0002',
          'qa-hydrant-camera-0002',
          'no_hydrant_at_location',
          'camera',
          'Técnico QA sintético',
          'qa-brigade',
          'qa/qa-fixtures/qa-user',
        ],
        status: JournalStatus.prepared,
        preparedAt: DateTime.utc(2026, 8, 29, 12),
        actor: 'qa-user',
        deviceId: 'qa-device',
        correlationId: 'qa-pending-camera-safe',
        schemaVersion: 2,
      );
      await OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      ).save(pending);
      final journalRecovery = await initialLab.run('pending-journal');
      expect(journalRecovery.totalWrites, greaterThan(0));
      expect(
        OperationJournalRepository(
          Hive.box<String>('operation_journal_v1'),
        ).find(pending.operationId)?.status,
        JournalStatus.needsRecovery,
      );
      expect((await initialLab.run('pending-journal-noop')).totalWrites, 0);
    },
  );
}

Future<void> _open(Directory root) async {
  Hive.init(root.path);
  for (final name in {
    ...qaObservedBootstrapBoxes,
    ...qaBootstrapSupportBoxes,
    'qa_fixture_runtime_v1',
  }) {
    await Hive.openBox<String>(name);
  }
}

Future<void> _reopen(Directory root) async {
  await Hive.close();
  await _open(root);
}

Future<void> _seedPhysicalEquivalent(
  Directory root,
  LocalDataScope scope, {
  String hydrantId = 'qa-hydrant-camera-0002',
  String? ownerUserId,
  String? createdBy,
  String? inspectorId,
  bool legacyIndex = false,
}) async {
  const reviewId = 'qa-review-camera-0002';
  final effectiveCreatedBy = createdBy ?? scope.userId;
  final effectiveInspectorId = inspectorId ?? scope.userId;
  final now = DateTime.utc(2026, 8, 29, 11);
  final references = <RvPhotoReference>[];
  for (var index = 1; index <= 5; index++) {
    final photoId = 'qa-photo-camera-${index.toString().padLeft(4, '0')}';
    final original = File('${root.path}/$photoId.jpg');
    final bytes = [0xff, 0xd8, index, 0xff, 0xd9];
    await original.writeAsBytes(bytes, flush: true);
    final hash = sha256.convert(bytes).toString();
    final photo = InspectionPhoto(
      id: photoId,
      hydrantId: hydrantId,
      inspectionId: reviewId,
      category: 'no_hydrant_at_location',
      source: PhotoSource.camera,
      originalFilename: '$photoId.jpg',
      normalizedFilename: '$photoId.jpg',
      localPath: original.path,
      thumbnailPath: original.path,
      mimeType: 'image/jpeg',
      fileSize: await original.length(),
      width: 1,
      height: 1,
      sha256: hash,
      receivedSha256: hash,
      capturedAt: now.add(Duration(seconds: index)),
      capturedByUserId: scope.userId.trim(),
      capturedByName: 'Técnico QA sintético',
      brigadeId: 'qa-brigade',
      deviceId: 'qa-device',
      createdAt: now.add(Duration(seconds: index)),
      updatedAt: now.add(Duration(seconds: index)),
    );
    await Hive.box<String>(
      'inspection_photos_v1',
    ).put(photoId, jsonEncode(photo.toJson()));
    await Hive.box<String>('media_work_queue_v1').put(
      photoId,
      MediaWorkItemCodec.pending(
        photoId: photoId,
        inspectionId: reviewId,
        slotCode: photo.category,
      ),
    );
    if (index <= 4) {
      references.add(
        RvPhotoReference(
          photoId: photoId,
          slotCode: photo.category,
          status: RvPhotoUploadStatus.pending,
        ),
      );
    } else {
      await OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      ).save(
        OperationJournalEntry(
          operationId: photoId,
          operationType: JournalOperationType.capturePhoto,
          entityIds: [
            'camera-pending-v2',
            reviewId,
            hydrantId,
            'no_hydrant_at_location',
            'camera',
            'Técnico QA sintético',
            'qa-brigade',
            scope.namespace,
          ],
          documentWrites: [photoId],
          fileWrites: [original.path],
          queueWrites: [photoId],
          status: JournalStatus.queueWritten,
          preparedAt: now,
          actor: scope.userId.trim(),
          deviceId: 'qa-device',
          correlationId: photoId,
          schemaVersion: 2,
        ),
      );
    }
  }
  final draft = RvDraft(
    clientInspectionId: reviewId,
    hydrantId: hydrantId,
    accountNumber: 'QA-CAMERA-0002',
    fieldSessionId: scope.userId.trim(),
    checklistId: 'qa-checklist-inactive-v1',
    checklistVersion: 1,
    checklistSnapshot: const {'sections': []},
    photos: {'no_hydrant_at_location': references},
    photosStatus: RvPartStatus.pending,
    localStatus: RvLocalStatus.pendingPhotos,
    createdAt: now,
    updatedAt: now,
  );
  final inspection = VisualInspection(
    id: reviewId,
    hydrantId: hydrantId,
    source: HydrantSource.assigned,
    inspectorId: effectiveInspectorId,
    inspectorName: 'Técnico QA sintético',
    brigadeId: 'qa-brigade',
    brigadeName: 'QA aislado',
    deviceId: 'qa-device',
    startedAt: now,
    createdAt: now,
    createdBy: effectiveCreatedBy,
    updatedAt: now,
    updatedBy: 'qa-user',
    unknownFields: {
      RvDraftRepository.storageKey: draft.toJson(),
      'dataScope': {
        'environment': scope.environment,
        'accountId': scope.accountId,
        'ownerUserId': ownerUserId ?? scope.userId,
        'brigadeId': scope.brigadeId,
      },
      'qaFixture': true,
    },
  );
  await Hive.box<String>('visual_inspections_v1').put(
    reviewId,
    VersionedJsonCodec.encode(
      schemaVersion: inspection.schemaVersion,
      payload: inspection.toJson(),
    ),
  );
  await Hive.box<String>('active_inspection_index_v1').put(
    legacyIndex
        ? '$hydrantId:f02A'
        : buildF02AScopedKey(
            environment: scope.environment,
            accountId: scope.accountId,
            ownerUserId: ownerUserId ?? scope.userId,
            createdBy: effectiveCreatedBy,
            inspectorId: effectiveInspectorId,
            hydrantId: hydrantId,
          )!,
    reviewId,
  );
}
