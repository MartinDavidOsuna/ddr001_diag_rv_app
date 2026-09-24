// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:async';
import 'package:ddr001diag/features/map/map_page.dart';
import 'package:ddr001diag/features/home/rv_work_dashboard.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:dio/dio.dart';
import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:ddr001diag/features/inspections/domain/rv_inactive_contract.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/foundation_fakes.dart';
import '../helpers/hive_test_environment.dart';

void main() {
  wireTests();
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
              source: 'gps',
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
        id: '11111111-1111-4111-8111-111111111111',
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

  void scope([String user = 'qa-user']) => visual.setAccessScope(
    LocalDataScope(
      environment: 'test',
      accountId: 'test',
      userId: user,
      brigadeId: 'qa-brigade',
      role: 'field',
    ),
  );

  Future<RvDraft> closed() async {
    scope();
    final draft = await createDraft();
    await drafts.saveInactiveClosureDraft(
      clientInspectionId: draft.clientInspectionId,
      user: _user,
      comment: 'No se encontró hidrante en esta ubicación.',
    );
    final result = await drafts.closeAsInactive(
      clientInspectionId: draft.clientInspectionId,
      user: _user,
      comment: 'No se encontró hidrante en esta ubicación.',
    );
    scope();
    return result;
  }

  InspectionSyncCoordinator coordinator(_Remote remote) =>
      InspectionSyncCoordinator(
        drafts: drafts,
        remote: remote,
        photoBox: Hive.box<String>('inspection_photos_v1'),
        mediaQueue: Hive.box<String>('media_sync_queue'),
        mediaWorkQueue: Hive.box<String>('media_work_queue_v1'),
      );

  test(
    'historical offline closure uploads dedicated evidence, flushes receipt and survives restoration',
    () async {
      final draft = await closed();
      final original = draft.inactiveClosure!;
      final remote = _Remote();
      final result = await coordinator(remote).synchronize(draft, submit: true);
      expect(result.localStatus, RvLocalStatus.inactive);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(result.inactiveClosure!.idempotencyKey, original.idempotencyKey);
      expect(result.inactiveClosure!.closedAt, original.closedAt);
      expect(
        result.inactiveClosure!.normalizedPhotoHashes,
        original.normalizedPhotoHashes,
      );
      expect(remote.uploads, 1);
      expect(remote.commands.single.keys.toSet(), {
        'contractVersion',
        'idempotencyKey',
        'reasonCode',
        'comment',
        'closedAt',
        'location',
        'photoIds',
      });
      expect(remote.createdClient, draft.clientInspectionId);
      final restored = RvDraftRepository(
        visual,
      ).find(draft.clientInspectionId)!;
      expect(restored.inactiveClosure!.remoteReceipt, remote.receipt);
      expect(restored.inactiveClosure!.statusLabel, 'Ausente · sincronizada');
      expect(
        File('${environment.directory.path}/qa-evidence.jpg').existsSync(),
        isTrue,
      );
      expect(visual.activeForHydrant(draft.hydrantId), isNull);
    },
  );

  test(
    'API without capability leaves original closure pending without creating or uploading',
    () async {
      final draft = await closed();
      final remote = _Remote()..supported = false;
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.pendingApiContract,
      );
      expect(remote.uploads, 0);
      expect(remote.createdClient, isNull);
      expect(remote.commands, isEmpty);
      expect(result.lastSyncError, contains('no anuncia soporte'));
    },
  );

  test(
    'lost commit response is recovered after restart and same-user session without uploading again',
    () async {
      final draft = await closed();
      final remote = _Remote()..loseResponse = true;
      final pending = await coordinator(remote).synchronize(draft);
      expect(
        pending.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.pendingSync,
      );
      expect(remote.receipt, isNotNull);
      scope();
      await File('${environment.directory.path}/qa-evidence.jpg').delete();
      final result = await coordinator(
        remote,
      ).synchronize(pending, forceRetry: true);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(remote.uploads, 1);
      expect(remote.commands.length, 1);
    },
  );

  test(
    'flushed receipt completes interrupted metadata write without network',
    () async {
      final draft = await closed();
      final remote = _Remote();
      final receipt = remote.makeReceipt(
        inactiveClosureCommand(draft.inactiveClosure!),
      );
      await drafts.save(
        draft.copyWith(
          serverInspectionId: _Remote.id,
          inactiveClosure: RvInactiveClosure.fromJson({
            ...draft.inactiveClosure!.toJson(),
            'syncStatus': 'syncing',
            'remoteReceipt': receipt,
          }),
        ),
      );
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(remote.calls, 0);
    },
  );

  test(
    'another user cannot synchronize even if handed the old draft',
    () async {
      final draft = await closed();
      scope('another-user');
      final remote = _Remote();
      await coordinator(remote).synchronize(draft, forceRetry: true);
      expect(remote.calls, 0);
      expect(remote.uploads, 0);
    },
  );

  test(
    'session change during remote read prevents further mutations',
    () async {
      final draft = await closed();
      final remote = _Remote()..onLookup = () => scope('another-user');
      await coordinator(remote).synchronize(draft);
      expect(remote.createdClient, isNull);
      expect(remote.commands, isEmpty);
    },
  );

  test(
    'two coordinator instances cannot upload the same closure concurrently',
    () async {
      final draft = await closed();
      final gate = Completer<void>();
      final remote = _Remote()..gate = gate.future;
      final first = coordinator(remote).synchronize(draft);
      await Future<void>.delayed(Duration.zero);
      await coordinator(remote).synchronize(draft);
      gate.complete();
      await first;
      expect(remote.uploads, 1);
      expect(remote.commands.length, 1);
    },
  );

  test(
    'historical queue survives closing Hive and reopening with the same owner',
    () async {
      final draft = await closed();
      final original = draft.inactiveClosure!.toJson();
      expect(
        drafts.pendingInactiveClosures().single.clientInspectionId,
        draft.clientInspectionId,
      );
      await Hive.close();
      for (final name in stage4BoxNames) {
        await Hive.openBox<String>(name);
      }
      visual = VisualInspectionRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      );
      drafts = RvDraftRepository(visual);
      scope('another-user');
      expect(drafts.pendingInactiveClosures(), isEmpty);
      scope();
      final recovered = drafts.pendingInactiveClosures().single;
      expect(recovered.inactiveClosure!.toJson(), original);
      expect(recovered.localStatus, RvLocalStatus.inactive);
      final result = await coordinator(_Remote()).synchronize(recovered);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(drafts.pendingInactiveClosures(), isEmpty);
    },
  );

  test(
    'partial upload is reused after retry without ordinary checklist or duplicate photos',
    () async {
      final draft = await closed();
      final remote = _Remote()..failStatus = 503;
      final pending = await coordinator(remote).synchronize(draft);
      remote.failStatus = null;
      remote.existing = [
        RemotePhoto(
          id: draft.inactiveClosure!.photoIds.single,
          slotCode: noHydrantAtLocationPhotoSlot,
          status: 'verified',
        ),
      ];
      final result = await coordinator(
        remote,
      ).synchronize(pending, forceRetry: true);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(remote.uploads, 1);
      expect(remote.commands.map((c) => c['idempotencyKey']).toSet(), {
        draft.inactiveClosure!.idempotencyKey,
      });
    },
  );

  test(
    'wrong remote photo slot is an identity conflict and never overwritten',
    () async {
      final draft = await closed();
      final remote = _Remote()
        ..existing = [
          RemotePhoto(
            id: draft.inactiveClosure!.photoIds.single,
            slotCode: 'front_closed',
            status: 'verified',
          ),
        ];
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.conflict,
      );
      expect(
        result.inactiveClosure!.remoteDomainCode,
        'INACTIVE_EVIDENCE_IDENTITY_CONFLICT',
      );
      expect(remote.uploads, 0);
      expect(remote.commands, isEmpty);
    },
  );

  test(
    'Ausente does not count as normal sent or incomplete checklist and protects final status',
    () async {
      final draft = await closed();
      expect(const RvValidator().validate(draft).issues, isEmpty);
      final groups = RvWorkDashboardProjection.byHydrant(
        drafts: [draft],
        hydrants: [_hydrant],
      );
      expect(groups.values.every((ids) => ids.isEmpty), isTrue);
      expect(_hydrant.isActive, isTrue);
      await expectLater(
        drafts.save(draft.copyWith(localStatus: RvLocalStatus.submitted)),
        throwsStateError,
      );
      expect(
        drafts.find(draft.clientInspectionId)!.localStatus,
        RvLocalStatus.inactive,
      );
    },
  );

  test(
    'restores server inactive receipt as terminal without running ordinary upload',
    () async {
      scope();
      final draft = await createDraft();
      final closure = RvInactiveClosure(
        reasonCode: noHydrantAtLocationReasonCode,
        comment: 'No hay hidrante en el lugar.',
        location: draft.location!,
        closedAt: DateTime.utc(2026, 9, 22),
        closedByUserId: _user.id,
        closedByName: _user.fullName,
        brigadeId: _user.brigadeId,
        deviceId: _user.deviceId,
        photoIds: draft
            .photosFor(noHydrantAtLocationPhotoSlot)
            .map((p) => p.photoId)
            .toList(),
        idempotencyKey: 'inactive-test-original-key',
      );
      final remote = _Remote()
        ..receipt = _Remote().makeReceipt(inactiveClosureCommand(closure));
      final result = await coordinator(remote).restoreRemoteInactive(
        draft,
        RemoteInspection(
          id: _Remote.id,
          status: 'inactive',
          clientInspectionId: draft.clientInspectionId,
          inactiveClosure: remote.receipt,
        ),
      );
      expect(result.isInactive, isTrue);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(visual.activeForHydrant(draft.hydrantId), isNull);
      expect(remote.uploads, 0);
      expect(remote.commands, isEmpty);
    },
  );

  test('map absence filter is independent of master hydrant inactivity', () {
    expect(
      hydrantMatchesMapFilter(
        _hydrant,
        HydrantMapFilter.absent,
        hasAbsentReview: true,
      ),
      isTrue,
    );
    expect(hydrantMatchesMapFilter(_hydrant, HydrantMapFilter.absent), isFalse);
    expect(
      hydrantMatchesMapFilter(
        _hydrant,
        HydrantMapFilter.inactive,
        hasAbsentReview: true,
      ),
      isFalse,
    );
    expect(
      hydrantMatchesMapFilter(
        _hydrant,
        HydrantMapFilter.all,
        hasAbsentReview: true,
      ),
      isTrue,
    );
  });

  test(
    'receipt survives failed verified write and recovers without a second HTTP command',
    () async {
      final draft = await closed();
      visual = _FailVerifiedWriteVisual(
        documents: visual.documents,
        index: visual.index,
      );
      drafts = RvDraftRepository(visual);
      scope();
      final remote = _Remote();
      final failed = await coordinator(remote).synchronize(draft);
      expect(
        failed.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.pendingSync,
      );
      expect(
        drafts.find(draft.clientInspectionId)!.inactiveClosure!.remoteReceipt,
        remote.receipt,
      );
      final count = remote.calls;
      final recovered = await coordinator(
        remote,
      ).synchronize(failed, forceRetry: true);
      expect(
        recovered.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(remote.calls, count);
      expect(remote.commands.length, 1);
    },
  );

  test(
    '401 resumes with a renewed same-user session and original key',
    () async {
      final draft = await closed();
      final remote = _Remote()..failStatus = 401;
      final failed = await coordinator(remote).synchronize(draft);
      scope();
      remote.failStatus = null;
      final result = await coordinator(
        remote,
      ).synchronize(failed, forceRetry: true);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      expect(remote.commands.map((c) => c['idempotencyKey']).toSet(), {
        draft.inactiveClosure!.idempotencyKey,
      });
    },
  );

  test(
    'incompatible historical contract is preserved and stops automatic retry',
    () async {
      final draft = await closed();
      final closure = RvInactiveClosure.fromJson({
        ...draft.inactiveClosure!.toJson(),
        'location': {
          ...draft.inactiveClosure!.location.toJson(),
          'source': 'legacy_unknown',
        },
      });
      await drafts.save(draft.copyWith(inactiveClosure: closure));
      final remote = _Remote();
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.requiresReview,
      );
      expect(result.inactiveClosure!.location.source, 'legacy_unknown');
      expect(result.inactiveClosure!.idempotencyKey, closure.idempotencyKey);
      final calls = remote.calls;
      await coordinator(remote).synchronize(result);
      expect(remote.calls, calls);
      expect(remote.uploads, 0);
    },
  );

  test(
    'API millisecond normalization matches without changing original microseconds',
    () async {
      final draft = await closed();
      final original = DateTime.utc(2026, 9, 22, 20, 0, 0, 123, 456);
      final closure = RvInactiveClosure.fromJson({
        ...draft.inactiveClosure!.toJson(),
        'closedAt': original.toIso8601String(),
      });
      final command = inactiveClosureCommand(closure);
      final receipt = _Remote().makeReceipt({
        ...command,
        'closedAt': '2026-09-22T20:00:00.123Z',
      });
      expect(inactiveReceiptMatches(receipt, _Remote.id, closure), isTrue);
      expect(closure.closedAt, original);
    },
  );

  test(
    'remoteVerified without a persisted receipt remains queued and is reconciled',
    () async {
      final draft = await closed();
      await drafts.save(
        draft.copyWith(
          inactiveClosure: RvInactiveClosure.fromJson({
            ...draft.inactiveClosure!.toJson(),
            'syncStatus': 'remoteVerified',
          }),
        ),
      );
      expect(
        drafts.pendingInactiveClosures().single.clientInspectionId,
        draft.clientInspectionId,
      );
      final remote = _Remote()
        ..receipt = _Remote().makeReceipt(
          inactiveClosureCommand(draft.inactiveClosure!),
        );
      final result = await coordinator(remote).synchronize(draft);
      expect(isInactiveRemoteVerified(result), isTrue);
      expect(remote.uploads, 0);
      expect(drafts.pendingInactiveClosures(), isEmpty);
    },
  );

  test(
    'a matching receipt cannot confirm a locally invalid reason code',
    () async {
      final draft = await closed();
      final invalid = RvInactiveClosure.fromJson({
        ...draft.inactiveClosure!.toJson(),
        'reasonCode': 'OTHER_REASON',
      });
      final receipt = _Remote().makeReceipt(inactiveClosureCommand(invalid));
      expect(inactiveReceiptMatches(receipt, _Remote.id, invalid), isFalse);
    },
  );

  for (final field in ['capturedByUserId', 'inspectionId', 'category']) {
    test(
      'receipt recovery preserves local photo with conflicting $field',
      () async {
        final draft = await closed();
        final photoId = draft.inactiveClosure!.photoIds.single;
        final box = Hive.box<String>('inspection_photos_v1');
        final json = Map<String, dynamic>.from(
          jsonDecode(box.get(photoId)!) as Map,
        )..[field] = 'other-identity';
        final preserved = jsonEncode(json);
        await box.put(photoId, preserved);
        final remote = _Remote()
          ..receipt = _Remote().makeReceipt(
            inactiveClosureCommand(draft.inactiveClosure!),
          );
        final result = await coordinator(remote).synchronize(draft);
        expect(
          result.inactiveClosure!.syncStatus,
          RvInactiveClosureSyncStatus.conflict,
        );
        expect(
          result.inactiveClosure!.remoteDomainCode,
          'INACTIVE_LOCAL_EVIDENCE_IDENTITY_CONFLICT',
        );
        expect(box.get(photoId), preserved);
        expect(remote.uploads, 0);
        expect(remote.commands, isEmpty);
      },
    );
  }

  test(
    'multipart absence preserves photo UUID, slot, hash and original timestamp',
    () async {
      final draft = await closed();
      final photoId = draft.inactiveClosure!.photoIds.single;
      final photo = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(Hive.box<String>('inspection_photos_v1').get(photoId)!)
              as Map,
        ),
      );
      final adapter = FakeHttpAdapter((request) async {
        expect(request.path, '/inspections/${_Remote.id}/photos');
        final form = request.data as FormData;
        final fields = Map.fromEntries(form.fields);
        expect(fields['photoId'], photo.id);
        expect(fields['slotCode'], noHydrantAtLocationPhotoSlot);
        expect(fields['clientSha256'], photo.sha256);
        expect(
          fields['capturedAt'],
          photo.capturedAt.toUtc().toIso8601String(),
        );
        expect(form.files.single.key, 'photo');
        expect(form.files.single.value.contentType.toString(), 'image/jpeg');
        return ResponseBody.fromString(
          jsonEncode({
            'photoId': photo.id,
            'slotCode': noHydrantAtLocationPhotoSlot,
            'status': 'verified',
          }),
          201,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      final remote = InspectionRemoteRepository(
        ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'development',
            apiBaseUrlOverride: 'https://inactive-test.invalid/api/v1',
          ),
          sessionStorage: MemorySessionStorage(),
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      final result = await remote.uploadPhoto(
        _Remote.id,
        noHydrantAtLocationPhotoSlot,
        photo,
      );
      expect(result.id, photoId);
      expect(File(photo.localPath).existsSync(), isTrue);
      expect(
        sha256.convert(await File(photo.localPath).readAsBytes()).toString(),
        photo.sha256,
      );
    },
  );

  for (final status in [401, 404, 409, 422, 503]) {
    test(
      'HTTP $status preserves closure, reports error and classifies retry',
      () async {
        final draft = await closed();
        final remote = _Remote()..failStatus = status;
        final result = await coordinator(remote).synchronize(draft);
        expect(result.localStatus, RvLocalStatus.inactive);
        expect(
          result.inactiveClosure!.idempotencyKey,
          draft.inactiveClosure!.idempotencyKey,
        );
        expect(
          result.inactiveClosure!.syncStatus,
          status == 409
              ? RvInactiveClosureSyncStatus.conflict
              : [404, 422].contains(status)
              ? RvInactiveClosureSyncStatus.requiresReview
              : RvInactiveClosureSyncStatus.pendingSync,
        );
        expect(result.lastSyncError, isNotNull);
        final before = remote.commands.length;
        await coordinator(remote).synchronize(result);
        expect(remote.commands.length, before);
        expect(
          File('${environment.directory.path}/qa-evidence.jpg').existsSync(),
          isTrue,
        );
      },
    );
  }

  test(
    '409 with matching committed receipt resolves, real conflict stays preserved',
    () async {
      final draft = await closed();
      final remote = _Remote()..commitConflict = true;
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.remoteVerified,
      );
      final mismatch = _Remote()
        ..receipt = remote.makeReceipt({
          ...inactiveClosureCommand(draft.inactiveClosure!),
          'comment': 'Otro cierre totalmente distinto.',
        });
      await drafts.save(draft.copyWith(serverInspectionId: _Remote.id));
      final conflict = await coordinator(mismatch).synchronize(draft);
      expect(
        conflict.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.conflict,
      );
      expect(conflict.inactiveClosure!.remoteReceipt, mismatch.receipt);
      expect(conflict.inactiveClosure!.comment, draft.inactiveClosure!.comment);
      expect(mismatch.uploads, 0);
    },
  );

  test(
    'invalid server evidence is actionable and distinct from identity conflict',
    () async {
      final draft = await closed();
      final remote = _Remote()..validEvidence = false;
      final result = await coordinator(remote).synchronize(draft);
      expect(
        result.inactiveClosure!.syncStatus,
        RvInactiveClosureSyncStatus.requiresReview,
      );
      expect(
        result.inactiveClosure!.remoteDomainCode,
        'INACTIVE_EVIDENCE_REQUIRED',
      );
      expect(remote.commands, isEmpty);
    },
  );

  test(
    'receipt identity ignores UUID case/order but rejects content differences',
    () async {
      final draft = await closed();
      final c = draft.inactiveClosure!;
      final remote = _Remote();
      final command = inactiveClosureCommand(c);
      final receipt = remote.makeReceipt({
        ...command,
        'photoIds': c.photoIds
            .map((id) => id.toUpperCase())
            .toList()
            .reversed
            .toList(),
      });
      expect(inactiveReceiptMatches(receipt, _Remote.id, c), isTrue);
      expect(
        inactiveReceiptMatches(
          {...receipt, 'inspectionId': 'other'},
          _Remote.id,
          c,
        ),
        isFalse,
      );
      expect(
        inactiveReceiptMatches(
          {
            ...receipt,
            'closure': {...command, 'idempotencyKey': 'other-key-1234567'},
          },
          _Remote.id,
          c,
        ),
        isFalse,
      );
    },
  );
}

class _Remote extends InspectionRemoteRepository {
  _Remote()
    : super(
        ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'development',
            apiBaseUrlOverride: 'https://inactive-test.invalid/api/v1',
          ),
          sessionStorage: MemorySessionStorage(),
        ),
      );
  static const id = '22222222-2222-4222-8222-222222222222';
  bool supported = true,
      loseResponse = false,
      commitConflict = false,
      validEvidence = true;
  int calls = 0, uploads = 0;
  int? failStatus;
  String? createdClient;
  Future<void>? gate;
  void Function()? onLookup;
  Map<String, dynamic>? receipt;
  List<RemotePhoto> existing = [];
  final commands = <Map<String, dynamic>>[];
  Map<String, dynamic> makeReceipt(Map<String, dynamic> command) => {
    'inspectionId': id,
    'status': 'inactive',
    'statusLabel': 'Ausente',
    'alreadyClosed': false,
    'receivedAt': '2026-09-24T12:00:00.000Z',
    'closure': command,
  };
  @override
  Future<bool> supportsInactiveClosure() async {
    calls++;
    await gate;
    return supported;
  }

  @override
  Future<RemoteInspection?> findByClientInspectionId(String clientId) async {
    calls++;
    onLookup?.call();
    return receipt == null && createdClient == null
        ? null
        : RemoteInspection(
            id: id,
            status: receipt == null ? 'draft' : 'inactive',
            clientInspectionId: clientId,
            inactiveClosure: receipt,
          );
  }

  @override
  Future<RemoteInspection> create(RvDraft draft) async {
    createdClient = draft.clientInspectionId;
    return RemoteInspection(
      id: id,
      status: 'draft',
      clientInspectionId: createdClient,
    );
  }

  @override
  Future<RemoteInspection> get(String id) async => RemoteInspection(
    id: id,
    status: receipt == null ? 'draft' : 'inactive',
    inactiveClosure: receipt,
  );
  @override
  Future<List<RemotePhoto>> photos(String id) async => existing;
  @override
  Future<RemotePhoto> uploadPhoto(
    String id,
    String slotCode,
    InspectionPhoto photo,
  ) async {
    expect(slotCode, noHydrantAtLocationPhotoSlot);
    uploads++;
    return RemotePhoto(
      id: photo.id,
      slotCode: slotCode,
      status: 'verified',
      sha256: photo.sha256,
    );
  }

  @override
  Future<List<RemotePhotoIntegrity>> verifyPhotosBatch(
    Iterable<String> ids,
  ) async => [
    for (final id in ids)
      RemotePhotoIntegrity(
        photoId: id,
        status: validEvidence
            ? PhotoIntegrityStatus.confirmed
            : PhotoIntegrityStatus.missingOriginal,
        originalPresent: validEvidence,
        thumbnailPresent: validEvidence,
        storageVerified: validEvidence,
        mapped: true,
        mappingStatus: PhotoMappingStatus.mapped,
        retryable: true,
        repairable: true,
      ),
  ];
  @override
  Future<Map<String, dynamic>> closeInactive(
    String id,
    Map<String, dynamic> command,
  ) async {
    commands.add(command);
    if (failStatus != null)
      throw ApiException(
        ApiErrorKind.serverError,
        'Fallo simulado visible',
        statusCode: failStatus,
        domainCode: failStatus == 422
            ? 'INACTIVE_EVIDENCE_INVALID'
            : 'TEST_ERROR',
      );
    receipt = makeReceipt(command);
    if (loseResponse)
      throw const ApiException(ApiErrorKind.timeout, 'Respuesta perdida');
    if (commitConflict)
      throw const ApiException(
        ApiErrorKind.validation,
        'Conflicto tras commit',
        statusCode: 409,
      );
    return receipt!;
  }

  @override
  Future<RemoteInspection> submit(String id) async =>
      throw StateError('NEVER SUBMIT ABSENCE');
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

void wireTests() {
  test(
    'HTTP 422 retains the evidence domain code for actionable classification',
    () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/inspections/id/inactive'),
          response: Response(
            requestOptions: RequestOptions(path: '/inspections/id/inactive'),
            statusCode: 422,
            data: {
              'code': 'INACTIVE_EVIDENCE_INVALID',
              'detail': 'La fotografía no está disponible.',
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(error.domainCode, 'INACTIVE_EVIDENCE_INVALID');
      expect(error.statusCode, 422);
    },
  );

  for (final status in [200, 201]) {
    test(
      'real repository accepts HTTP $status receipt and serializes only contract fields',
      () async {
        final command = <String, dynamic>{
          'contractVersion': 1,
          'idempotencyKey': 'inactive-original-key',
          'reasonCode': noHydrantAtLocationReasonCode,
          'comment': 'No hay hidrante en esta ubicación.',
          'closedAt': '2026-09-22T20:00:00.000Z',
          'location': {
            'latitude': 28.1,
            'longitude': -110.1,
            'source': 'gps',
            'capturedAt': '2026-09-22T19:59:00.000Z',
          },
          'photoIds': ['11111111-1111-4111-8111-111111111111'],
        };
        final receipt = _Remote().makeReceipt(command);
        final adapter = FakeHttpAdapter((request) async {
          expect(request.method, 'POST');
          expect(request.path, '/inspections/${_Remote.id}/inactive');
          expect(request.data, command);
          return ResponseBody.fromString(
            jsonEncode(receipt),
            status,
            headers: {
              'content-type': ['application/json'],
            },
          );
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = InspectionRemoteRepository(
          ApiClient(
            config: AppConfig.fromEnvironment(
              environmentOverride: 'development',
              apiBaseUrlOverride: 'https://inactive-test.invalid/api/v1',
            ),
            sessionStorage: MemorySessionStorage(),
            dio: dio,
          ),
        );
        expect(await repository.closeInactive(_Remote.id, command), receipt);
      },
    );
  }
  test(
    'real repository reads capability strictly and restores inactive receipt from by-client',
    () async {
      Object? flag = 'true';
      final receipt = _Remote().makeReceipt({});
      final adapter = FakeHttpAdapter(
        (request) async => ResponseBody.fromString(
          jsonEncode(
            request.path == '/version'
                ? {
                    'features': {'rvInactiveClosure': flag},
                  }
                : {
                    'inspection_id': _Remote.id,
                    'client_inspection_id': 'local-client',
                    'status': 'inactive',
                    'inactiveClosure': receipt,
                  },
          ),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      final repository = InspectionRemoteRepository(
        ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'development',
            apiBaseUrlOverride: 'https://inactive-test.invalid/api/v1',
          ),
          sessionStorage: MemorySessionStorage(),
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      expect(await repository.supportsInactiveClosure(), isFalse);
      flag = null;
      expect(await repository.supportsInactiveClosure(), isFalse);
      flag = true;
      expect(await repository.supportsInactiveClosure(), isTrue);
      final result = await repository.findByClientInspectionId('local-client');
      expect(result!.status, 'inactive');
      expect(result.clientInspectionId, 'local-client');
      expect(result.inactiveClosure, receipt);
    },
  );
}

class _FailVerifiedWriteVisual extends VisualInspectionRepository {
  _FailVerifiedWriteVisual({required super.documents, required super.index});
  bool fail = true;
  @override
  Future<void> saveCompletedSyncMetadata({
    required String inspectionId,
    required String storageKey,
    required Object metadata,
  }) async {
    if (fail &&
        metadata is Map &&
        (metadata['inactiveClosure'] as Map?)?['syncStatus'] ==
            'remoteVerified') {
      fail = false;
      throw StateError('Simulated interrupted final metadata write');
    }
    await super.saveCompletedSyncMetadata(
      inspectionId: inspectionId,
      storageKey: storageKey,
      metadata: metadata,
    );
  }
}
