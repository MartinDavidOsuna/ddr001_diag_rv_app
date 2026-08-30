import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/app/local_recovery_pipeline.dart';
import 'package:ddr001diag/data/local/media_work_item_codec.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
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
    await environment.open(
      boxes: {
        ...stage4BoxNames,
        'quarantine_documents_v1',
        'integrity_audit_reports_v1',
      },
    );
    visual = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    drafts = RvDraftRepository(visual);
  });

  tearDown(() => environment.close());

  Future<void> localBootstrapPass() async {
    await LocalRecoveryPipeline(
      visualRepository: visual,
      drafts: drafts,
      operationJournalBox: Hive.box<String>('operation_journal_v1'),
      quarantineBox: Hive.box<String>('quarantine_documents_v1'),
      recoveryBox: Hive.box<String>('rv_recovery_v1'),
      snapshotBox: Hive.box<String>('rv_recovery_snapshots_v1'),
      indexBox: Hive.box<String>('active_inspection_index_v1'),
      syncQueueBox: Hive.box<String>('sync_queue'),
      photoBox: Hive.box<String>('inspection_photos_v1'),
      mediaQueueBox: Hive.box<String>('media_sync_queue'),
      integrityReportBox: Hive.box<String>('integrity_audit_reports_v1'),
    ).run();
  }

  test('segunda pasada local completa hace cero escrituras', () async {
    final now = DateTime.utc(2026, 8, 28);
    final file = File('${environment.directory.path}/stable-photo.jpg');
    await file.writeAsBytes([1, 2, 3, 4], flush: true);
    const reviewId = 'bootstrap-stable-review';
    const photoId = 'bootstrap-stable-photo';
    final draft = RvDraft(
      clientInspectionId: reviewId,
      hydrantId: 'bootstrap-hydrant',
      accountNumber: '2392-QA',
      fieldSessionId: 'qa-user',
      checklistId: 'qa-checklist',
      checklistVersion: 1,
      checklistSnapshot: const {'sections': []},
      answers: {
        'diameter': RvAnswer(
          questionId: 'diameter',
          sectionId: 'qa',
          answerType: 'text',
          value: 'synthetic',
          updatedAt: now,
        ),
      },
      photos: const {
        'front_closed': [
          RvPhotoReference(
            photoId: photoId,
            slotCode: 'front_closed',
            status: RvPhotoUploadStatus.verified,
          ),
        ],
      },
      retryCount: 9,
      createdAt: now,
      updatedAt: now,
    );
    await visual.documents.put(
      reviewId,
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: VisualInspection(
          id: reviewId,
          hydrantId: draft.hydrantId,
          source: HydrantSource.fieldCreated,
          startedAt: now,
          createdAt: now,
          createdBy: 'qa-user',
          updatedAt: now,
          unknownFields: {RvDraftRepository.storageKey: draft.toJson()},
        ).toJson(),
      ),
    );
    final photo = InspectionPhoto(
      id: photoId,
      hydrantId: draft.hydrantId,
      inspectionId: reviewId,
      category: 'front_closed',
      source: PhotoSource.camera,
      originalFilename: 'stable.jpg',
      normalizedFilename: 'stable.jpg',
      localPath: file.path,
      thumbnailPath: file.path,
      mimeType: 'image/jpeg',
      fileSize: 4,
      width: 1,
      height: 1,
      sha256: 'stable-hash',
      capturedAt: now,
      capturedByUserId: 'qa-user',
      capturedByName: 'QA',
      brigadeId: 'qa-brigade',
      deviceId: 'qa-device',
      syncStatus: MediaSyncStatus.verified,
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    );
    await Hive.box<String>(
      'inspection_photos_v1',
    ).put(photoId, jsonEncode(photo.toJson()));
    final queue = MediaWorkItemCodec.pending(
      photoId: photoId,
      inspectionId: reviewId,
      slotCode: photo.category,
      status: 'verify',
    );
    await Hive.box<String>('media_work_queue_v1').put(photoId, queue);
    await Hive.box<String>('media_sync_queue').put(photoId, queue);

    await localBootstrapPass();
    final boxes = <String, Box<String>>{
      for (final name in [
        'visual_inspections_v1',
        'active_inspection_index_v1',
        'inspection_photos_v1',
        'media_work_queue_v1',
        'media_sync_queue',
        'operation_journal_v1',
        'quarantine_documents_v1',
        'integrity_audit_reports_v1',
        'rv_recovery_v1',
        'rv_recovery_snapshots_v1',
      ])
        name: Hive.box<String>(name),
    };
    final before = {
      for (final entry in boxes.entries)
        entry.key: Map<Object, String>.from(entry.value.toMap()),
    };
    final writes = {for (final name in boxes.keys) name: <BoxEvent>[]};
    final subscriptions = [
      for (final entry in boxes.entries)
        entry.value.watch().listen(writes[entry.key]!.add),
    ];

    await localBootstrapPass();
    await Future<void>.delayed(Duration.zero);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }

    for (final entry in boxes.entries) {
      expect(writes[entry.key], isEmpty, reason: entry.key);
      expect(entry.value.toMap(), before[entry.key], reason: entry.key);
    }
    expect(drafts.find(reviewId)!.answers['diameter']!.value, 'synthetic');
    expect(
      drafts.find(reviewId)!.photos.entries.single.value.single.photoId,
      photoId,
    );
    expect(file.existsSync(), isTrue);
  });
}
