import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/core/media/reliable_photo_service.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/data/local/media_work_item_codec.dart';
import 'package:ddr001diag/data/local/completed_visual_report_resolver.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/diagnostics/rv_diagnostic_export_service.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:ddr001diag/features/inspections/domain/rv_visual_document_classification.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_inactive_closure_dialog.dart';
import 'package:ddr001diag/features/inspections/presentation/inspection_photo_projection.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_inspection_controller.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_steps_one_two.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_summary_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../helpers/foundation_fakes.dart';
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

  Future<RvDraft> createDraft({
    bool withLocation = true,
    bool withPhoto = true,
    bool badHash = false,
  }) async {
    final draft = await drafts.openOrCreate(
      hydrant: _hydrant,
      user: _user,
      checklist: _checklist,
    );
    final now = DateTime.utc(2026, 8, 28, 18);
    var updated = draft.copyWith(
      location: withLocation
          ? RvLocationSample(
              latitude: 0.1234567,
              longitude: -0.7654321,
              horizontalAccuracy: 3.2,
              source: 'qa_fixture',
              capturedAt: now,
            )
          : null,
      locationStatus: withLocation
          ? RvPartStatus.pending
          : RvPartStatus.notCaptured,
      updatedAt: now,
    );
    if (withPhoto) {
      final file = File('${environment.directory.path}/qa-evidence.jpg');
      final bytes = List<int>.generate(2048, (index) => index % 251);
      await file.writeAsBytes(bytes, flush: true);
      final photo = InspectionPhoto(
        id: 'qa-photo-inactive-001',
        hydrantId: updated.hydrantId,
        inspectionId: updated.clientInspectionId,
        category: noHydrantAtLocationPhotoSlot,
        source: PhotoSource.camera,
        originalFilename: 'qa-source.jpg',
        normalizedFilename: 'qa-evidence.jpg',
        localPath: file.path,
        thumbnailPath: file.path,
        mimeType: 'image/jpeg',
        fileSize: bytes.length,
        width: 1600,
        height: 1200,
        sha256: badHash
            ? ''.padRight(64, '0')
            : sha256.convert(bytes).toString(),
        receivedSha256: sha256.convert(bytes).toString(),
        capturedAt: now,
        capturedByUserId: _user.id,
        capturedByName: _user.fullName,
        brigadeId: _user.brigadeId,
        deviceId: _user.deviceId,
        createdAt: now,
        updatedAt: now,
      );
      await Hive.box<String>(
        'inspection_photos_v1',
      ).put(photo.id, jsonEncode(photo.toJson()));
      updated = updated.copyWith(
        photos: {
          ...updated.photos,
          noHydrantAtLocationPhotoSlot: [
            RvPhotoReference(
              photoId: photo.id,
              slotCode: noHydrantAtLocationPhotoSlot,
              status: RvPhotoUploadStatus.pending,
            ),
          ],
        },
        photosStatus: RvPartStatus.pending,
      );
    }
    await drafts.save(updated);
    return updated;
  }

  test('legacy draft remains readable without inactive closure fields', () {
    final now = DateTime.utc(2026, 8, 28);
    final legacy = RvDraft(
      clientInspectionId: 'legacy-id',
      hydrantId: 'legacy-hydrant',
      accountNumber: 'QA-LEGACY',
      fieldSessionId: 'legacy-user',
      checklistId: 'legacy-checklist',
      checklistVersion: 1,
      checklistSnapshot: _checklist.toJson(),
      createdAt: now,
      updatedAt: now,
    ).toJson()..remove('inactiveClosure');

    final restored = RvDraft.fromJson(legacy);

    expect(restored.inactiveClosure, isNull);
    expect(restored.localStatus, RvLocalStatus.pendingCreate);
    expect(restored.isReadOnly, isFalse);
  });

  test('requires a valid coordinate, comment and dedicated photo', () async {
    final noLocation = await createDraft(withLocation: false, withPhoto: false);
    await expectLater(
      drafts.closeAsInactive(
        clientInspectionId: noLocation.clientInspectionId,
        user: _user,
        comment: 'No se encontró equipo en el punto.',
      ),
      throwsA(isA<StateError>()),
    );
    expect(drafts.find(noLocation.clientInspectionId)?.isReadOnly, isFalse);

    await expectLater(
      drafts.closeAsInactive(
        clientInspectionId: noLocation.clientInspectionId,
        user: _user,
        comment: '   ',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('closure is journaled, lossless, read-only and idempotent', () async {
    final source = await createDraft();
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    final physicalBefore = await File(
      '${environment.directory.path}/qa-evidence.jpg',
    ).readAsBytes();

    final closed = await drafts.closeAsInactive(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: '  No existe hidrante visible en esta ubicación.  ',
      closedAt: DateTime.utc(2026, 8, 28, 19),
    );

    expect(closed.localStatus, RvLocalStatus.inactive);
    expect(closed.isInactive, isTrue);
    expect(closed.isReadOnly, isTrue);
    expect(
      closed.inactiveClosure?.comment,
      'No existe hidrante visible en esta ubicación.',
    );
    expect(closed.inactiveClosure?.reasonCode, noHydrantAtLocationReasonCode);
    expect(
      closed.inactiveClosure?.syncStatus,
      RvInactiveClosureSyncStatus.pendingApiContract,
    );
    expect(closed.inactiveClosure?.closedByUserId, _user.id);
    expect(closed.inactiveClosure?.deviceId, _user.deviceId);
    expect(closed.inactiveClosure?.photoIds, ['qa-photo-inactive-001']);
    expect(visual.activeForHydrant(source.hydrantId), isNull);
    expect(
      visual.findById(source.clientInspectionId)?.status,
      InspectionStatus.completed,
    );
    expect(
      await File('${environment.directory.path}/qa-evidence.jpg').readAsBytes(),
      physicalBefore,
    );

    final journal = Hive.box<String>('operation_journal_v1').values
        .map(
          (raw) => OperationJournalEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        )
        .where(
          (entry) =>
              entry.operationType ==
              JournalOperationType.closeInactiveVisualReport,
        )
        .single;
    expect(journal.status, JournalStatus.committed);

    final repeated = await drafts.closeAsInactive(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    expect(
      repeated.inactiveClosure?.closedAt,
      closed.inactiveClosure?.closedAt,
    );
    expect(
      Hive.box<String>(
        'operation_journal_v1',
      ).values.where((raw) => raw.contains('closeInactiveVisualReport')),
      hasLength(1),
    );
  });

  test('hash mismatch preserves editable draft and active index', () async {
    final source = await createDraft(badHash: true);
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );

    await expectLater(
      drafts.closeAsInactive(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: 'No existe hidrante visible en esta ubicación.',
      ),
      throwsA(isA<StateError>()),
    );

    expect(drafts.find(source.clientInspectionId)?.isInactive, isFalse);
    expect(
      visual.activeForHydrant(source.hydrantId)?.id,
      source.clientInspectionId,
    );
    expect(
      await File('${environment.directory.path}/qa-evidence.jpg').exists(),
      isTrue,
    );
  });

  test('ordinary synchronization never submits an inactive closure', () async {
    final source = await createDraft();
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    final closed = await drafts.closeAsInactive(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://network-must-not-be-used.invalid/api/v1',
      ),
      sessionStorage: MemorySessionStorage(),
      dio: Dio(),
    );
    final coordinator = InspectionSyncCoordinator(
      drafts: drafts,
      remote: InspectionRemoteRepository(client),
      photoBox: Hive.box<String>('inspection_photos_v1'),
      mediaQueue: Hive.box<String>('media_sync_queue'),
    );

    final result = await coordinator.synchronize(closed, submit: true);

    expect(result, same(closed));
    expect(
      result.inactiveClosure?.syncStatus,
      RvInactiveClosureSyncStatus.pendingApiContract,
    );
    expect(result.serverInspectionId, isNull);
  });

  test('dedicated evidence blocks normal submit before any API use', () async {
    final source = await createDraft();

    final result = const RvValidator().validate(source);

    expect(
      result.issues.map((issue) => issue.code),
      contains('inactive_evidence_requires_closure'),
    );
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://network-must-not-be-used.invalid/api/v1',
      ),
      sessionStorage: MemorySessionStorage(),
      dio: Dio(),
    );
    final coordinator = InspectionSyncCoordinator(
      drafts: drafts,
      remote: InspectionRemoteRepository(client),
      photoBox: Hive.box<String>('inspection_photos_v1'),
      mediaQueue: Hive.box<String>('media_sync_queue'),
    );

    final unchanged = await coordinator.synchronize(source, submit: true);
    expect(unchanged.serverInspectionId, isNull);
    expect(unchanged.localStatus, source.localStatus);
  });

  test('partial comment is a durable draft and remains active', () async {
    final source = await createDraft(withPhoto: false);

    final saved = await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: '  Observación parcial  ',
    );
    final reopened = drafts.find(source.clientInspectionId)!;

    expect(saved.inactiveClosureDraft?.comment, 'Observación parcial');
    expect(reopened.inactiveClosureDraft?.draftId, isNotEmpty);
    expect(reopened.localStatus, isNot(RvLocalStatus.inactive));
    expect(reopened.isReadOnly, isFalse);
    expect(
      visual.activeForHydrant(source.hydrantId)?.id,
      source.clientInspectionId,
    );
    expect(
      const RvValidator().validate(reopened).issues.map((issue) => issue.code),
      contains('inactive_evidence_requires_closure'),
    );
  });

  test(
    'empty cancel produces no draft and repeated saves reuse one draft',
    () async {
      final source = await createDraft(withPhoto: false);
      final unchanged = await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: '   ',
      );
      expect(unchanged.inactiveClosureDraft, isNull);
      expect(
        Hive.box<String>(
          'operation_journal_v1',
        ).values.where((raw) => raw.contains('saveInactiveClosureDraft')),
        isEmpty,
      );

      final cameraRecoveryPlaceholder = await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: '',
        allowEmpty: true,
      );
      expect(cameraRecoveryPlaceholder.inactiveClosureDraft, isNotNull);
      final cameraCancelled = await drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      );
      expect(cameraCancelled.inactiveClosureDraft, isNull);
      expect(cameraCancelled.photosFor(noHydrantAtLocationPhotoSlot), isEmpty);

      final first = await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: 'Comentario inicial del reporte.',
      );
      final second = await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: 'Comentario actualizado del reporte.',
      );
      expect(
        second.inactiveClosureDraft?.draftId,
        first.inactiveClosureDraft?.draftId,
      );
      expect(second.inactiveClosureDraft?.comment, contains('actualizado'));
    },
  );

  test(
    'camera cancellation removes only its empty recovery placeholder',
    () async {
      final source = await createDraft(withPhoto: false);
      final client = ApiClient(
        config: AppConfig.fromEnvironment(
          environmentOverride: 'development',
          apiBaseUrlOverride: 'https://network-must-not-be-used.invalid/api/v1',
        ),
        sessionStorage: MemorySessionStorage(),
        dio: Dio(),
      );
      final controller = RvInspectionController(
        drafts: drafts,
        coordinator: InspectionSyncCoordinator(
          drafts: drafts,
          remote: InspectionRemoteRepository(client),
          photoBox: Hive.box<String>('inspection_photos_v1'),
          mediaQueue: Hive.box<String>('media_sync_queue'),
        ),
        hydrant: _hydrant,
        user: _user,
        checklist: _checklist,
        photoService: ReliablePhotoService(
          picker: _CancelledPhotoPicker(),
          documentsDirectory: () async => environment.directory,
        ),
      )..draft = source;

      await controller.addInactiveEvidencePhoto(
        ImageSource.camera,
        comment: '',
      );

      expect(controller.draft?.inactiveClosureDraft, isNull);
      expect(
        controller.draft?.photosFor(noHydrantAtLocationPhotoSlot),
        isEmpty,
      );
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    },
  );

  test(
    'discard archives only dedicated local evidence and unlocks normal flow',
    () async {
      final source = await createDraft();
      final file = File('${environment.directory.path}/qa-evidence.jpg');
      final bytes = await file.readAsBytes();
      final saved = await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: 'Reporte iniciado por error en QA.',
      );
      await Hive.box<String>('media_work_queue_v1').put(
        'qa-photo-inactive-001',
        MediaWorkItemCodec.pending(
          photoId: 'qa-photo-inactive-001',
          inspectionId: source.clientInspectionId,
          slotCode: noHydrantAtLocationPhotoSlot,
        ),
      );
      await Hive.box<String>('media_sync_queue').put(
        'qa-photo-inactive-001',
        MediaWorkItemCodec.pending(
          photoId: 'qa-photo-inactive-001',
          inspectionId: source.clientInspectionId,
          slotCode: noHydrantAtLocationPhotoSlot,
        ),
      );

      final discarded = await drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      );
      final photo = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(
                Hive.box<String>(
                  'inspection_photos_v1',
                ).get('qa-photo-inactive-001')!,
              )
              as Map,
        ),
      );

      expect(saved.inactiveClosureDraft, isNotNull);
      expect(discarded.inactiveClosureDraft, isNull);
      expect(discarded.photosFor(noHydrantAtLocationPhotoSlot), isEmpty);
      expect(discarded.isReadOnly, isFalse);
      expect(photo.isDeleted, isTrue);
      expect(await file.readAsBytes(), bytes);
      expect(
        MediaWorkItemCodec.statusOf(
          photo.id,
          Hive.box<String>('media_work_queue_v1').get(photo.id),
        ),
        'discardedLocalInactiveDraft',
      );
      expect(
        MediaWorkItemCodec.statusOf(
          photo.id,
          Hive.box<String>('media_sync_queue').get(photo.id),
        ),
        'discardedLocalInactiveDraft',
      );
      expect(
        const RvValidator()
            .validate(discarded)
            .issues
            .map((issue) => issue.code),
        isNot(contains('inactive_evidence_requires_closure')),
      );
      final operation = Hive.box<String>('operation_journal_v1').values
          .map(
            (raw) => OperationJournalEntry.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            ),
          )
          .where(
            (entry) =>
                entry.operationType ==
                JournalOperationType.discardInactiveClosureDraft,
          )
          .single;
      expect(operation.status, JournalStatus.committed);
      expect(
        diagnosticPhotoRowIsPending({
          'syncStatus': photo.syncStatus.name,
          'rvPhotoReferenceStatus': null,
          'mediaWorkQueueStatus': 'discardedLocalInactiveDraft',
          'deletedAt': photo.deletedAt?.toIso8601String(),
          'diagnosticClassification': 'DISCARDED_LOCAL_INACTIVE_DRAFT',
        }),
        isFalse,
      );

      final repeated = await drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      );
      expect(repeated.photosFor(noHydrantAtLocationPhotoSlot), isEmpty);
      expect(await file.readAsBytes(), bytes);
    },
  );

  test(
    'discard refuses remote evidence and preserves reference and file',
    () async {
      final source = await createDraft();
      await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: 'Reporte que no debe descartarse remotamente.',
      );
      final box = Hive.box<String>('inspection_photos_v1');
      final raw = Map<String, dynamic>.from(
        jsonDecode(box.get('qa-photo-inactive-001')!) as Map,
      )..['uploadedAt'] = DateTime.utc(2026, 8, 28, 19).toIso8601String();
      await box.put('qa-photo-inactive-001', jsonEncode(raw));

      await expectLater(
        drafts.discardInactiveClosureDraft(
          clientInspectionId: source.clientInspectionId,
          user: _user,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        drafts
            .find(source.clientInspectionId)
            ?.photosFor(noHydrantAtLocationPhotoSlot),
        isNotEmpty,
      );
      expect(
        File('${environment.directory.path}/qa-evidence.jpg').existsSync(),
        isTrue,
      );
    },
  );

  test('discard refuses a photo also referenced by another slot', () async {
    final source = await createDraft();
    final current = drafts.find(source.clientInspectionId)!;
    final dedicated = current.photosFor(noHydrantAtLocationPhotoSlot).single;
    await drafts.save(
      current.copyWith(
        photos: {
          ...current.photos,
          'front_closed': [
            RvPhotoReference(
              photoId: dedicated.photoId,
              slotCode: 'front_closed',
              status: dedicated.status,
            ),
          ],
        },
      ),
    );
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'Reporte con referencia compartida inválida.',
    );

    await expectLater(
      drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      ),
      throwsA(isA<StateError>()),
    );
    final photo = InspectionPhoto.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(
              Hive.box<String>('inspection_photos_v1').get(dedicated.photoId)!,
            )
            as Map,
      ),
    );
    expect(photo.isDeleted, isFalse);
  });

  test('discard refuses a photo referenced by another review', () async {
    final source = await createDraft();
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'Reporte con referencia cruzada inválida.',
    );
    final inspection = visual.findById(source.clientInspectionId)!;
    final otherDraftJson = {
      ...drafts.find(source.clientInspectionId)!.toJson(),
      'clientInspectionId': 'qa-other-review',
      'hydrantId': 'qa-other-hydrant',
    };
    final otherPayload = inspection.toJson()
      ..['id'] = 'qa-other-review'
      ..['hydrantId'] = 'qa-other-hydrant'
      ..[RvDraftRepository.storageKey] = otherDraftJson;
    await visual.documents.put(
      'qa-other-review',
      VersionedJsonCodec.encode(
        schemaVersion: inspection.schemaVersion,
        payload: otherPayload,
      ),
    );

    await expectLater(
      drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      drafts
          .find(source.clientInspectionId)
          ?.photosFor(noHydrantAtLocationPhotoSlot),
      isNotEmpty,
    );
  });

  test('confirmed inactive evidence can never be discarded', () async {
    final source = await createDraft();
    const comment = 'No existe hidrante visible en esta ubicación.';
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: comment,
    );
    await drafts.closeAsInactive(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: comment,
    );

    await expectLater(
      drafts.discardInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      File('${environment.directory.path}/qa-evidence.jpg').existsSync(),
      isTrue,
    );
  });

  test(
    'confirmed closure identity rejects changed comment or photo hash',
    () async {
      final source = await createDraft();
      const comment = 'No existe hidrante visible en esta ubicación.';
      await drafts.saveInactiveClosureDraft(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: comment,
      );
      final closed = await drafts.closeAsInactive(
        clientInspectionId: source.clientInspectionId,
        user: _user,
        comment: comment,
      );
      expect(
        closed.inactiveClosure?.idempotencyKey,
        startsWith('inactive-v1-'),
      );

      await expectLater(
        drafts.closeAsInactive(
          clientInspectionId: source.clientInspectionId,
          user: _user,
          comment: 'Comentario diferente y no equivalente.',
        ),
        throwsA(isA<StateError>()),
      );
      final photoBox = Hive.box<String>('inspection_photos_v1');
      final raw = Map<String, dynamic>.from(
        jsonDecode(photoBox.get('qa-photo-inactive-001')!) as Map,
      )..['sha256'] = ''.padRight(64, 'f');
      await photoBox.put('qa-photo-inactive-001', jsonEncode(raw));
      await expectLater(
        drafts.closeAsInactive(
          clientInspectionId: source.clientInspectionId,
          user: _user,
          comment: comment,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('location validation rejects unsafe values and missing metadata', () {
    final valid = RvLocationSample(
      latitude: 1,
      longitude: -1,
      horizontalAccuracy: 0,
      source: 'qa',
      capturedAt: DateTime.utc(2026, 8, 28),
    );
    expect(valid.isValid, isTrue);
    for (final sample in [
      RvLocationSample(
        latitude: double.nan,
        longitude: -1,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 91,
        longitude: -1,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: double.infinity,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 0,
        longitude: 0,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: -1,
        horizontalAccuracy: -1,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: -1,
        horizontalAccuracy: double.nan,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: -1,
        horizontalAccuracy: double.infinity,
        source: 'qa',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: -1,
        source: ' ',
        capturedAt: valid.capturedAt,
      ),
      RvLocationSample(
        latitude: 1,
        longitude: -1,
        source: 'qa',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    ]) {
      expect(sample.isValid, isFalse);
    }
    expect(manualCoordinateError('NaN', isLatitude: true), isNotNull);
    expect(manualCoordinateError('Infinity', isLatitude: false), isNotNull);
  });

  test('inactive completion has explicit classification', () async {
    final source = await createDraft();
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    await drafts.closeAsInactive(
      clientInspectionId: source.clientInspectionId,
      user: _user,
      comment: 'No existe hidrante visible en esta ubicación.',
    );
    final document = visual.findById(source.clientInspectionId)!;

    expect(document.status, InspectionStatus.completed);
    expect(
      classifyRvVisualDocument(document),
      RvVisualDocumentKind.inactiveClosure,
    );
    expect(isNormalCompletedRvDocument(document), isFalse);
    expect(
      CompletedVisualReportResolver(
        visual,
      ).findLatestCompletedForHydrant(_hydrant).source,
      CompletedVisualResolutionSource.none,
    );
    await expectLater(
      visual.createRevision(
        document,
        const AppUser(
          id: 'qa-supervisor',
          fullName: 'Supervisor QA',
          email: 'supervisor@example.invalid',
          role: 'supervisor',
          brigadeId: 'qa-brigade',
          brigadeName: 'QA aislado',
          deviceId: 'qa-supervisor-device',
        ),
        'No debe crearse desde un cierre inactivo.',
      ),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('exit choice is explicit, accessible and supports large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: const Scaffold(body: InactiveDraftExitDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guardar para continuar después'), findsOneWidget);
    expect(find.text('Descartar este reporte'), findsOneWidget);
    expect(find.text('Seguir editando'), findsOneWidget);
    expect(
      find.textContaining('Las demás respuestas y fotografías'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inactive dialog shows a newly persisted photo and releases projection',
    (tester) async {
      late RvDraft source;
      late RvDraft withPhoto;
      await tester.runAsync(() async {
        source = await createDraft(withPhoto: false);
        withPhoto = await createDraft();
      });
      expect(withPhoto.clientInspectionId, source.clientInspectionId);
      final client = ApiClient(
        config: AppConfig.fromEnvironment(
          environmentOverride: 'development',
          apiBaseUrlOverride: 'https://network-must-not-be-used.invalid/api/v1',
        ),
        sessionStorage: MemorySessionStorage(),
        dio: Dio(),
      );
      final controller = RvInspectionController(
        drafts: drafts,
        coordinator: InspectionSyncCoordinator(
          drafts: drafts,
          remote: InspectionRemoteRepository(client),
          photoBox: Hive.box<String>('inspection_photos_v1'),
          mediaQueue: Hive.box<String>('media_sync_queue'),
        ),
        hydrant: _hydrant,
        user: _user,
        checklist: _checklist,
        photoService: ReliablePhotoService(
          picker: _CancelledPhotoPicker(),
          documentsDirectory: () async => environment.directory,
        ),
      )..draft = source;
      final projection = InspectionPhotoDocumentProjection();
      var dialogBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RvInactiveClosureDialog(
              controller: controller,
              photoProjection: projection,
              onBuild: () => dialogBuilds++,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('inactive-photo-required')), findsOne);
      expect(projection.retainedDocuments, 0);

      await tester.runAsync(controller.initialize);
      await tester.pump();

      expect(find.byKey(const ValueKey('inactive-photo-count')), findsOne);
      expect(
        find.byKey(const ValueKey('inactive-preview-qa-photo-inactive-001')),
        findsOne,
      );
      expect(projection.hiveReads, 1);
      expect(projection.jsonDecodes, 1);
      expect(
        find.byKey(const ValueKey('inactive-static-repaint-boundary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inactive-previews-repaint-boundary')),
        findsOneWidget,
      );
      final buildsBeforeUnchangedNotifications = dialogBuilds;
      for (var notification = 0; notification < 20; notification++) {
        controller.notifyListeners();
        await tester.pump();
      }
      expect(dialogBuilds, buildsBeforeUnchangedNotifications);
      controller.processingPhoto = true;
      controller.notifyListeners();
      await tester.pump();
      expect(dialogBuilds, buildsBeforeUnchangedNotifications + 1);
      controller.processingPhoto = false;
      controller.notifyListeners();
      await tester.pump();
      for (var rebuild = 0; rebuild < 20; rebuild++) {
        await tester.pump();
      }
      expect(projection.hiveReads, 1);
      expect(projection.jsonDecodes, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(projection.retainedDocuments, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed inactive summary selectively refreshes thumbnail metadata',
    (tester) async {
      late RvDraft closed;
      await tester.runAsync(() async {
        final source = await createDraft();
        await drafts.saveInactiveClosureDraft(
          clientInspectionId: source.clientInspectionId,
          user: _user,
          comment: 'No existe hidrante visible en esta ubicación.',
        );
        closed = await drafts.closeAsInactive(
          clientInspectionId: source.clientInspectionId,
          user: _user,
          comment: 'No existe hidrante visible en esta ubicación.',
        );
      });
      final closure = closed.inactiveClosure!;
      final projection = InspectionPhotoDocumentProjection();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RvInactiveClosureSummary(
              closure: closure,
              photoProjection: projection,
            ),
          ),
        ),
      );
      expect(
        find.byKey(
          const ValueKey('inactive-summary-photo-qa-photo-inactive-001'),
        ),
        findsOne,
      );
      expect(projection.hiveReads, 1);

      final box = Hive.box<String>('inspection_photos_v1');
      final original = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(box.get(closure.photoIds.single)!) as Map,
        ),
      );
      final regenerated = File(
        '${environment.directory.path}/qa-evidence-regenerated.jpg',
      );
      await tester.runAsync(() async {
        await regenerated.writeAsBytes([1, 2, 3, 4], flush: true);
        await box.put(
          original.id,
          jsonEncode({
            ...original.toJson(),
            'thumbnailPath': regenerated.path,
            'updatedAt': DateTime.utc(2026, 8, 28, 22).toIso8601String(),
          }),
        );
      });
      await tester.pump();
      await tester.pump();

      expect(projection.hiveReads, 2);
      expect(projection.jsonDecodes, 2);
      expect(
        find.byKey(
          ValueKey(
            'inactive-summary-thumbnail-${original.id}-${regenerated.path}',
          ),
        ),
        findsOne,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(projection.retainedDocuments, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test('comment validator trims and enforces compatible bounds', () {
    expect(inactiveClosureCommentError('     '), isNotNull);
    expect(inactiveClosureCommentError('123456789'), isNotNull);
    expect(inactiveClosureCommentError(' Evidencia QA suficiente '), isNull);
    expect(
      inactiveClosureCommentError(
        ''.padRight(inactiveClosureCommentMaxLength + 1, 'x'),
      ),
      isNotNull,
    );
  });

  test('step 1 enables the action only after persisted coordinates', () async {
    final source = await createDraft(withLocation: false, withPhoto: false);
    expect(
      canStartInactiveClosure(
        draft: source,
        busy: false,
        processingPhoto: false,
      ),
      isFalse,
    );

    final located = source.copyWith(
      location: RvLocationSample(
        latitude: 1,
        longitude: -1,
        source: 'qa_fixture',
        capturedAt: DateTime.utc(2026, 8, 28),
      ),
    );
    expect(
      canStartInactiveClosure(
        draft: located,
        busy: false,
        processingPhoto: false,
      ),
      isTrue,
    );
    expect(
      canStartInactiveClosure(
        draft: located,
        busy: true,
        processingPhoto: false,
      ),
      isFalse,
    );
    expect(
      canStartInactiveClosure(
        draft: located,
        busy: false,
        processingPhoto: true,
      ),
      isFalse,
    );
  });
}

const _user = AppUser(
  id: 'qa-user',
  fullName: 'Técnico QA',
  email: 'qa@example.invalid',
  role: 'field',
  brigadeId: 'qa-brigade',
  brigadeName: 'QA aislado',
  deviceId: 'qa-device',
);

const _hydrant = Hydrant(
  id: 'qa-hydrant-inactive',
  code: 'QA-NO-HYDRANT',
  locality: 'Sintético',
  parcel: 'Sintético',
  priority: PriorityLevel.low,
  access: AccessType.vehicle,
  syncStatus: SyncStatus.local,
  f02a: InspectionSummary(
    type: InspectionType.f02A,
    status: InspectionStatus.pending,
    progress: 0,
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
  id: 'qa-inactive-checklist',
  code: 'RV-QA-INACTIVE',
  version: 1,
  title: 'QA inactive',
  etag: 'qa-inactive-v1',
  cachedAt: DateTime.utc(2026, 8, 28),
  sections: const [],
);

class _CancelledPhotoPicker implements PhotoPicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    String? captureId,
    String? durablePath,
  }) async => null;

  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();

  @override
  Future<DurableCameraOutcome> durableCameraOutcome(String captureId) async =>
      DurableCameraOutcome.unknown;

  @override
  Future<void> clearDurableCameraOutcome(String captureId) async {}
}
