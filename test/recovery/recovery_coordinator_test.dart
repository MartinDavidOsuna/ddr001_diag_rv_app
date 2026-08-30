import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/data/local/integrity_audit_service.dart';
import 'package:ddr001diag/data/local/operation_journal_repository.dart';
import 'package:ddr001diag/data/local/quarantine_repository.dart';
import 'package:ddr001diag/data/local/recovery_coordinator.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/integrity/integrity_models.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;
  late OperationJournalRepository journal;
  late RecoveryCoordinator recovery;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    recovery = RecoveryCoordinator(
      auditService: const IntegrityAuditService(),
      journal: journal,
      quarantine: QuarantineRepository(Hive.box<String>('quarantine_v1')),
    );
  });
  tearDown(() => environment.close());

  OperationJournalEntry entry({
    required String id,
    required JournalStatus status,
    JournalOperationType type = JournalOperationType.createVisualReport,
    List<String> entities = const [],
    List<String> documents = const [],
    List<String> queues = const [],
  }) => OperationJournalEntry(
    operationId: id,
    operationType: type,
    entityIds: entities,
    documentWrites: documents,
    queueWrites: queues,
    status: status,
    preparedAt: DateTime.utc(2026, 7, 15),
    actor: 'actor',
    deviceId: 'device',
    correlationId: id,
  );

  test('prepared vacío se compensa sin inventar documentos', () async {
    await journal.save(entry(id: 'op-empty', status: JournalStatus.prepared));

    final outcome = await recovery.recoverJournalEntry(
      journal.find('op-empty')!,
    );

    expect(outcome, JournalRecoveryOutcome.safelyCompensated);
    expect(journal.find('op-empty')?.status, JournalStatus.failed);
    expect(Hive.box<String>('visual_inspections_v1'), isEmpty);
  });

  test(
    'captura externa prepared queda disponible para retrieveLostData',
    () async {
      await journal.save(
        entry(
          id: 'camera-photo',
          status: JournalStatus.prepared,
          type: JournalOperationType.capturePhoto,
          entities: const [
            'camera-pending-v1',
            'inspection-1',
            'hydrant-1',
            'top',
            'camera',
          ],
        ),
      );

      final outcome = await recovery.recoverJournalEntry(
        journal.find('camera-photo')!,
      );

      expect(outcome, JournalRecoveryOutcome.manualReview);
      expect(journal.find('camera-photo')?.status, JournalStatus.needsRecovery);
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    },
  );

  test(
    'captura durable prepared queda reservada para recovery de cámara',
    () async {
      await journal.save(
        entry(
          id: 'durable-camera-photo',
          status: JournalStatus.prepared,
          type: JournalOperationType.capturePhoto,
          entities: const [
            'camera-pending-v2',
            'inspection-1',
            'hydrant-1',
            'top',
            'camera',
            'User',
            'brigade',
            'qa/scope',
          ],
        ),
      );

      final outcome = await recovery.recoverJournalEntry(
        journal.find('durable-camera-photo')!,
      );

      expect(outcome, JournalRecoveryOutcome.manualReview);
      expect(
        journal.find('durable-camera-photo')?.status,
        JournalStatus.needsRecovery,
      );
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    },
  );

  test('documentsWritten repara índice inequívoco y confirma', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-1',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {'id': 'rv-1', 'hydrantId': 'h-1', 'status': 'inProgress'},
      ),
    );
    await journal.save(
      entry(
        id: 'op-rv',
        status: JournalStatus.documentsWritten,
        documents: const ['rv-1'],
      ),
    );

    final outcome = await recovery.recoverJournalEntry(journal.find('op-rv')!);

    expect(outcome, JournalRecoveryOutcome.committed);
    expect(
      Hive.box<String>('active_inspection_index_v1').get('h-1:f02A'),
      'rv-1',
    );
    expect(journal.find('op-rv')?.status, JournalStatus.committed);
  });

  test('documentsWritten conserva el índice scoped del documento', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-scoped',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'rv-scoped',
          'hydrantId': 'h-scoped',
          'status': 'inProgress',
          'dataScope': {
            'environment': 'QA',
            'accountId': 'QA Fixtures',
            'ownerUserId': 'QA User',
          },
        },
      ),
    );
    await journal.save(
      entry(
        id: 'op-rv-scoped',
        status: JournalStatus.documentsWritten,
        documents: const ['rv-scoped'],
      ),
    );

    final outcome = await recovery.recoverJournalEntry(
      journal.find('op-rv-scoped')!,
    );

    expect(outcome, JournalRecoveryOutcome.committed);
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).get('qa/qa%20fixtures/qa%20user/h-scoped/f02A'),
      'rv-scoped',
    );
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).containsKey('h-scoped:f02A'),
      isFalse,
    );
  });

  test('scope parcial deriva propietario persistido del documento', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-partial-scope',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'rv-partial-scope',
          'hydrantId': 'h-partial',
          'status': 'inProgress',
          'createdBy': 'QA Owner',
          'dataScope': {'environment': 'QA', 'accountId': 'QA Fixtures'},
        },
      ),
    );
    await journal.save(
      entry(
        id: 'op-rv-partial-scope',
        status: JournalStatus.documentsWritten,
        documents: const ['rv-partial-scope'],
      ),
    );

    expect(
      await recovery.recoverJournalEntry(journal.find('op-rv-partial-scope')!),
      JournalRecoveryOutcome.committed,
    );
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).get('qa/qa%20fixtures/qa%20owner/h-partial/f02A'),
      'rv-partial-scope',
    );
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).containsKey('h-partial:f02A'),
      isFalse,
    );
  });

  test('owner vacío usa inspector y canonicaliza hydrant reservado', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-inspector-fallback',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'rv-inspector-fallback',
          'hydrantId': ' A+B/01 ',
          'status': 'inProgress',
          'createdBy': ' ',
          'inspectorId': ' INSPECTOR-1 ',
          'dataScope': {
            'environment': ' Production ',
            'accountId': ' DDR 001 ',
            'ownerUserId': '   ',
          },
        },
      ),
    );
    await journal.save(
      entry(
        id: 'op-rv-inspector-fallback',
        status: JournalStatus.documentsWritten,
        documents: const ['rv-inspector-fallback'],
      ),
    );

    expect(
      await recovery.recoverJournalEntry(
        journal.find('op-rv-inspector-fallback')!,
      ),
      JournalRecoveryOutcome.committed,
    );
    expect(
      Hive.box<String>(
        'active_inspection_index_v1',
      ).get('production/ddr%20001/inspector-1/a%2Bb%2F01/f02A'),
      'rv-inspector-fallback',
    );
  });

  test('F02B conserva índice legacy aunque el documento tenga scope', () async {
    await Hive.box<String>('functional_inspections_v1').put(
      'functional-scoped',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'functional-scoped',
          'hydrantId': 'h-functional',
          'status': 'inProgress',
          'createdBy': 'QA Owner',
          'dataScope': {
            'environment': 'QA',
            'accountId': 'QA Fixtures',
            'ownerUserId': 'QA Owner',
          },
        },
      ),
    );
    await journal.save(
      entry(
        id: 'op-functional-scoped',
        status: JournalStatus.documentsWritten,
        type: JournalOperationType.createFunctionalReport,
        documents: const ['functional-scoped'],
      ),
    );

    expect(
      await recovery.recoverJournalEntry(journal.find('op-functional-scoped')!),
      JournalRecoveryOutcome.committed,
    );
    expect(
      Hive.box<String>(
        'active_functional_inspection_index_v1',
      ).get('h-functional:f02B'),
      'functional-scoped',
    );
    expect(
      Hive.box<String>(
        'active_functional_inspection_index_v1',
      ).keys.where((key) => '$key'.contains('/')),
      isEmpty,
    );
  });

  test('save inactive draft recovers by exact correlation identity', () async {
    await Hive.box<String>('visual_inspections_v1').put(
      'rv-draft',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'rv-draft',
          'rvDynamicDraft': {
            'inactiveClosureDraft': {'draftId': 'draft-correlation'},
          },
        },
      ),
    );
    final operation = OperationJournalEntry(
      operationId: 'save-draft-operation',
      operationType: JournalOperationType.saveInactiveClosureDraft,
      entityIds: const ['rv-draft'],
      documentWrites: const ['rv-draft'],
      status: JournalStatus.prepared,
      preparedAt: DateTime.utc(2026, 8, 28),
      actor: 'actor',
      deviceId: 'device',
      correlationId: 'draft-correlation',
    );
    await journal.save(operation);

    expect(
      await recovery.recoverJournalEntry(operation),
      JournalRecoveryOutcome.committed,
    );
    expect(
      journal.find(operation.operationId)?.status,
      JournalStatus.committed,
    );
  });

  test(
    'partial inactive discard converges without deleting physical file',
    () async {
      final now = DateTime.utc(2026, 8, 28);
      final file = File('${environment.directory.path}/discard-recovery.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);
      const inspectionId = 'rv-discard';
      const photoId = 'photo-discard';
      await Hive.box<String>('inspection_photos_v1').put(
        photoId,
        jsonEncode(
          InspectionPhoto(
            id: photoId,
            hydrantId: 'hydrant-discard',
            inspectionId: inspectionId,
            category: noHydrantAtLocationPhotoSlot,
            source: PhotoSource.camera,
            originalFilename: 'source.jpg',
            normalizedFilename: 'discard-recovery.jpg',
            localPath: file.path,
            thumbnailPath: file.path,
            mimeType: 'image/jpeg',
            fileSize: 4,
            width: 2,
            height: 2,
            sha256: 'hash',
            receivedSha256: 'received',
            capturedAt: now,
            capturedByUserId: 'actor',
            capturedByName: 'QA',
            brigadeId: 'qa',
            deviceId: 'device',
            syncStatus: MediaSyncStatus.pendingUpload,
            createdAt: now,
            updatedAt: now,
            deletedAt: now,
          ).toJson(),
        ),
      );
      await Hive.box<String>('visual_inspections_v1').put(
        inspectionId,
        VersionedJsonCodec.encode(
          schemaVersion: 1,
          payload: {
            'id': inspectionId,
            'rvDynamicDraft': {
              'localStatus': 'pendingPhotos',
              'inactiveClosureDraft': {'draftId': 'draft-discard'},
              'photos': {
                noHydrantAtLocationPhotoSlot: [
                  {
                    'photoId': photoId,
                    'slotCode': noHydrantAtLocationPhotoSlot,
                  },
                ],
              },
            },
          },
        ),
      );
      final operation = OperationJournalEntry(
        operationId: 'discard-draft-discard',
        operationType: JournalOperationType.discardInactiveClosureDraft,
        entityIds: const [inspectionId, photoId],
        documentWrites: const [inspectionId, photoId],
        queueWrites: const [photoId],
        fileWrites: [file.path],
        status: JournalStatus.filesWritten,
        preparedAt: now,
        actor: 'actor',
        deviceId: 'device',
        correlationId: 'draft-discard',
      );
      await journal.save(operation);

      expect(
        await recovery.recoverJournalEntry(operation),
        JournalRecoveryOutcome.committed,
      );
      final recoveredPhoto = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(Hive.box<String>('inspection_photos_v1').get(photoId)!)
              as Map,
        ),
      );
      final recoveredDraft =
          VersionedJsonCodec.decode(
                Hive.box<String>('visual_inspections_v1').get(inspectionId)!,
              ).payload['rvDynamicDraft']
              as Map;
      expect(recoveredPhoto.isDeleted, isTrue);
      expect(file.existsSync(), isTrue);
      expect(recoveredDraft['inactiveClosureDraft'], isNull);
      expect(
        Map<String, dynamic>.from(
          recoveredDraft['photos'] as Map,
        ).containsKey(noHydrantAtLocationPhotoSlot),
        isFalse,
      );
      expect(
        journal.find(operation.operationId)?.status,
        JournalStatus.committed,
      );
      expect(
        await recovery.recoverJournalEntry(operation),
        JournalRecoveryOutcome.committed,
      );
      expect(file.existsSync(), isTrue);
    },
  );

  test(
    'process death during inactive closure removes only its active index',
    () async {
      await Hive.box<String>('visual_inspections_v1').put(
        'rv-inactive',
        VersionedJsonCodec.encode(
          schemaVersion: 1,
          payload: {
            'id': 'rv-inactive',
            'hydrantId': 'h-inactive',
            'status': 'completed',
          },
        ),
      );
      await Hive.box<String>(
        'active_inspection_index_v1',
      ).put('h-inactive:f02A', 'rv-inactive');
      await Hive.box<String>(
        'active_inspection_index_v1',
      ).put('h-other:f02A', 'rv-other');
      await journal.save(
        entry(
          id: 'op-inactive',
          status: JournalStatus.documentsWritten,
          type: JournalOperationType.closeInactiveVisualReport,
          entities: const ['rv-inactive'],
          documents: const ['rv-inactive'],
        ),
      );

      final outcome = await recovery.recoverJournalEntry(
        journal.find('op-inactive')!,
      );

      expect(outcome, JournalRecoveryOutcome.committed);
      expect(
        Hive.box<String>(
          'active_inspection_index_v1',
        ).containsKey('h-inactive:f02A'),
        isFalse,
      );
      expect(
        Hive.box<String>('active_inspection_index_v1').get('h-other:f02A'),
        'rv-other',
      );
    },
  );

  test(
    'queueWritten incompleto queda recuperable y conserva evidencia',
    () async {
      final source = entry(
        id: 'op-partial',
        status: JournalStatus.queueWritten,
        documents: const ['missing-report'],
        queues: const ['missing-queue'],
      );
      await journal.save(source);

      final outcome = await recovery.recoverJournalEntry(source);

      expect(outcome, JournalRecoveryOutcome.manualReview);
      expect(
        journal.find(source.operationId)?.status,
        JournalStatus.needsRecovery,
      );
      expect(
        journal.find(source.operationId)?.lastError,
        contains('queueWritten'),
      );
    },
  );

  test('auditor detecta índice huérfano y recuperación lo retira', () async {
    await Hive.box<String>(
      'active_inspection_index_v1',
    ).put('h-1:f02A', 'missing');

    final summary = await recovery.runLightweight();

    expect(
      summary.audit.issues.any((issue) => issue.entityId == 'missing'),
      isTrue,
    );
    expect(
      Hive.box<String>('active_inspection_index_v1').containsKey('h-1:f02A'),
      isFalse,
    );
    expect(summary.repaired, greaterThanOrEqualTo(1));
  });

  test('índice scoped huérfano queda para revisión y no se adopta', () async {
    const foreignKey = 'production/field/other-user/h-foreign/f02A';
    await Hive.box<String>(
      'active_inspection_index_v1',
    ).put(foreignKey, 'missing-foreign');

    final summary = await recovery.runLightweight();

    final issue = summary.audit.issues.singleWhere(
      (value) => value.entityId == 'missing-foreign',
    );
    expect(issue.recommendedAction, RecoveryAction.manualReview);
    expect(issue.repairableAutomatically, isFalse);
    expect(
      Hive.box<String>('active_inspection_index_v1').get(foreignKey),
      'missing-foreign',
    );
  });

  test('muerte tras guardar foto conserva y espera enlace del draft', () async {
    final original = File('${environment.directory.path}/photo-crash.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await Hive.box<String>('inspection_photos_v1').put(
      'photo-crash',
      jsonEncode({
        'id': 'photo-crash',
        'inspectionId': 'rv-crash',
        'localPath': original.path,
      }),
    );
    final operation = entry(
      id: 'photo-crash',
      status: JournalStatus.photoSaved,
      type: JournalOperationType.capturePhoto,
      entities: const ['photo-crash', 'rv-crash'],
      documents: const ['photo-crash'],
      queues: const ['photo-crash'],
    );
    await journal.save(operation);

    expect(
      await recovery.recoverJournalEntry(operation),
      JournalRecoveryOutcome.manualReview,
    );
    expect(original.existsSync(), isTrue);
    expect(
      Hive.box<String>('media_work_queue_v1').containsKey('photo-crash'),
      isTrue,
    );
    expect(journal.find('photo-crash')?.status, JournalStatus.needsRecovery);
  });

  test(
    'reinicio tras enlazar draft completa journal y cola idempotentemente',
    () async {
      final original = File('${environment.directory.path}/photo-linked.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await Hive.box<String>('inspection_photos_v1').put(
        'photo-linked',
        jsonEncode({
          'id': 'photo-linked',
          'inspectionId': 'rv-linked',
          'localPath': original.path,
        }),
      );
      await Hive.box<String>('visual_inspections_v1').put(
        'rv-linked',
        VersionedJsonCodec.encode(
          schemaVersion: 1,
          payload: {
            'id': 'rv-linked',
            'rvDynamicDraft': {
              'photos': {
                'front_closed': [
                  {'photoId': 'photo-linked'},
                ],
              },
            },
          },
        ),
      );
      final operation = entry(
        id: 'photo-linked',
        status: JournalStatus.draftLinked,
        type: JournalOperationType.capturePhoto,
        entities: const ['photo-linked', 'rv-linked'],
        documents: const ['photo-linked'],
        queues: const ['photo-linked'],
      );
      await journal.save(operation);

      expect(
        await recovery.recoverJournalEntry(operation),
        JournalRecoveryOutcome.committed,
      );
      expect(
        await recovery.recoverJournalEntry(journal.find('photo-linked')!),
        JournalRecoveryOutcome.committed,
      );
      expect(journal.find('photo-linked')?.status, JournalStatus.committed);
      expect(original.existsSync(), isTrue);
    },
  );
}
