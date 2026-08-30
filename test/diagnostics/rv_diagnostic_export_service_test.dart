import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/data/local/sync_queue_repository.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/features/auth/data/field_session_models.dart';
import 'package:ddr001diag/features/auth/data/session_secure_storage.dart';
import 'package:ddr001diag/features/diagnostics/rv_diagnostic_export_service.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/data/sync_receipt_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../helpers/hive_test_environment.dart';

class _Storage implements SessionStorage {
  final session = const FieldSession(
    sessionId: 'work-session',
    userId: 'user-1',
    accessToken: 'secret-access-token',
    refreshToken: 'secret-refresh-token',
    installationId: 'installation-12345678',
    name: 'Inspector',
    crew: 'RESIDENTE',
    crewId: 'crew-1',
  );
  @override
  Future<String> installationId() async => session.installationId;
  @override
  Future<FieldSession?> read() async => session;
  @override
  Future<void> clear() => throw UnsupportedError('read only');
  @override
  Future<void> save(FieldSession session) =>
      throw UnsupportedError('read only');
}

void main() {
  late HiveTestEnvironment environment;
  late Directory output;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    output = await Directory.systemTemp.createTemp('rv_export_test_');
  });

  tearDown(() async {
    await environment.close();
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  RvDiagnosticExportService service({
    DiagnosticRemoteProvider? remoteProvider,
  }) {
    final visual = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    return RvDiagnosticExportService(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'test',
        apiBaseUrlOverride: 'https://example.invalid/api/v1',
      ),
      packageInfo: PackageInfo(
        appName: 'DDR001',
        packageName: 'com.aquafim.ddr001diag',
        version: '0.2.38',
        buildNumber: '60',
      ),
      sessionStorage: _Storage(),
      visualRepository: visual,
      drafts: RvDraftRepository(visual),
      syncQueue: SyncQueueRepository(Hive.box<String>('sync_queue')),
      hydrantBox: Hive.box<String>('local_hydrants_v1'),
      activeIndexBox: Hive.box<String>('active_inspection_index_v1'),
      photoBox: Hive.box<String>('inspection_photos_v1'),
      mediaSyncBox: Hive.box<String>('media_sync_queue'),
      mediaWorkBox: Hive.box<String>('media_work_queue_v1'),
      diagnosticsBox: Hive.box<String>('rv_sync_diagnostics_v1'),
      receiptsBox: Hive.box<String>('rv_sync_receipts_v1'),
      deviceProvider: (id) async => {
        'installationId': id,
        'model': 'test-device',
      },
      directoryProvider: () async => output,
      remoteProvider: remoteProvider,
    );
  }

  test(
    'export offline es legible, sanitiza secretos/GPS y no modifica Hive',
    () async {
      final diagnostics = Hive.box<String>('rv_sync_diagnostics_v1');
      for (var index = 0; index < 1000; index++) {
        await diagnostics.put(
          'event-$index',
          jsonEncode({
            'timestamp': '2026-08-14T02:15:00Z',
            'accountNumber': '1134',
            'message': 'Bearer secret-access-token',
            'accessToken': 'secret-access-token',
            'refreshToken': 'secret-refresh-token',
            'latitude': 22.123456,
            'longitude': -102.123456,
          }),
        );
      }
      await Hive.box<String>('sync_queue').put('broken', '{not-json');
      final before = {
        for (final name in stage4BoxNames)
          if (Hive.isBoxOpen(name))
            name: Map<Object?, Object?>.from(Hive.box<String>(name).toMap()),
      };

      final result = await service().export(
        screenSummary: const {'home': {}, 'syncPage': {}},
        hydrants: const [],
        queryRemote: false,
      );
      final text = await result.file.readAsString();
      final decoded = jsonDecode(text) as Map<String, dynamic>;

      expect(decoded['schemaVersion'], 1);
      expect(decoded['diagnostics'], hasLength(1000));
      expect((decoded['syncQueue'] as List).single['unreadable'], true);
      expect(text, isNot(contains('secret-access-token')));
      expect(text, isNot(contains('secret-refresh-token')));
      expect(text, isNot(contains('Inspector')));
      expect(text, isNot(contains('RESIDENTE')));
      expect(text, isNot(contains('22.123456')));
      expect(text, isNot(contains('-102.123456')));
      expect(result.remoteSnapshotComplete, false);
      for (final entry in before.entries) {
        expect(
          Hive.box<String>(entry.key).toMap(),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('export incluye receipts sin mutar cajas operacionales', () async {
    final receipts = SyncReceiptRepository(
      Hive.box<String>('rv_sync_receipts_v1'),
    );
    await receipts.record(
      clientInspectionId: 'client-safe',
      serverInspectionId: 'server-safe',
      operation: 'inspection_read_reconcile',
      outcome: SyncReceiptOutcome.reconciledByRead,
      httpStatus: 200,
      requestId: 'request-safe',
      beforeLocalState: 'submitted',
      afterLocalState: 'submitted',
      remoteState: 'submitted',
      responseClassification: 'remote_terminal_state_confirmed',
    );
    final before = {
      for (final name in stage4BoxNames)
        name: Map<Object?, Object?>.from(Hive.box<String>(name).toMap()),
    };

    final result = await service().export(
      screenSummary: const {},
      hydrants: const [],
      queryRemote: false,
    );
    final decoded = jsonDecode(await result.file.readAsString()) as Map;

    expect(decoded['syncReceipts'], hasLength(1));
    expect((decoded['summary'] as Map)['totalSyncReceipts'], 1);
    for (final entry in before.entries) {
      expect(Hive.box<String>(entry.key).toMap(), entry.value);
    }
  });

  test('clasificaciones distinguen verified remoto, legacy y faltante', () {
    expect(
      classifyDiagnosticPhoto(
        localFileExists: true,
        remoteVerified: true,
        localVerified: false,
        mediaWorkStatus: 'pendingUpload',
        hasDraft: true,
        hasRemoteMatch: true,
      ),
      'REMOTE_VERIFIED_LOCAL_PENDING',
    );
    expect(
      classifyDiagnosticPhoto(
        localFileExists: true,
        remoteVerified: false,
        localVerified: true,
        mediaWorkStatus: 'pendingUpload',
        hasDraft: true,
        hasRemoteMatch: false,
      ),
      'LEGACY_QUEUE_STALE',
    );
    expect(
      classifyDiagnosticPhoto(
        localFileExists: false,
        remoteVerified: false,
        localVerified: false,
        mediaWorkStatus: null,
        hasDraft: true,
        hasRemoteMatch: false,
      ),
      'MISSING_LOCAL_FILE',
    );
  });

  test('cola JSON no oculta confirmación local persistida', () {
    final now = DateTime.utc(2026, 8, 28);
    final photo = InspectionPhoto(
      id: 'photo',
      hydrantId: 'hydrant',
      inspectionId: 'inspection',
      category: 'front_closed',
      source: PhotoSource.camera,
      originalFilename: 'photo.jpg',
      normalizedFilename: 'photo.jpg',
      localPath: '/preserved/photo.jpg',
      thumbnailPath: '/preserved/photo-thumb.jpg',
      mimeType: 'image/jpeg',
      fileSize: 1,
      width: 1,
      height: 1,
      sha256: 'a' * 64,
      capturedAt: now,
      capturedByUserId: 'user',
      capturedByName: 'Inspector',
      brigadeId: 'crew',
      deviceId: 'device',
      syncStatus: MediaSyncStatus.verified,
      integrityStatus: PhotoIntegrityStatus.confirmed,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      diagnosticLocalPhotoVerified(
        photo: photo,
        reference: const RvPhotoReference(
          photoId: 'photo',
          slotCode: 'front_closed',
          status: RvPhotoUploadStatus.verified,
        ),
        mediaQueueValue: '{"schemaVersion":2,"status":"verify"}',
        mediaWorkStatus: 'verified',
      ),
      isTrue,
    );
  });

  test(
    'comparte PRE, POST offline y diagnóstico actual sin archivos ajenos',
    () async {
      final pre = File('${output.path}/DDR001_RV_CERT_PRE_RECOVERY_A.json');
      final post = File(
        '${output.path}/DDR001_RV_CERT_POST_RECOVERY_OFFLINE_B.json',
      );
      final current = File('${output.path}/DDR001_RV_DIAGNOSTIC_v60_C.json');
      final unrelated = File('${output.path}/rv-diagnostic-old.txt');
      await pre.writeAsString('{}');
      await post.writeAsString('{}');
      await current.writeAsString('{}');
      await unrelated.writeAsString('old');

      final files = await service().certificationEvidenceFiles(
        currentDiagnostic: current,
      );

      expect(files.map((file) => p.basename(file.path)), {
        p.basename(pre.path),
        p.basename(post.path),
        p.basename(current.path),
      });
    },
  );

  test('429 detiene snapshot remoto pero conserva JSON local', () async {
    final visual = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    final now = DateTime.utc(2026, 8, 14);
    final draft = RvDraft(
      clientInspectionId: 'client-1134',
      hydrantId: 'local-1134',
      accountNumber: '1134',
      fieldSessionId: 'work-session',
      checklistId: 'rv-v2',
      checklistVersion: 2,
      checklistSnapshot: const {},
      createdAt: now,
      updatedAt: now,
    );
    await visual.save(
      VisualInspection(
        id: draft.clientInspectionId,
        hydrantId: draft.hydrantId,
        source: HydrantSource.fieldCreated,
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        createdBy: 'user-1',
        inspectorId: 'user-1',
        unknownFields: {'rvDynamicDraft': draft.toJson()},
      ),
    );

    final result =
        await service(
          remoteProvider: (_) async => throw const ApiException(
            ApiErrorKind.rateLimited,
            'Demasiadas solicitudes.',
            statusCode: 429,
          ),
        ).export(
          screenSummary: const {'home': {}, 'syncPage': {}},
          hydrants: const [],
        );
    final json = jsonDecode(await result.file.readAsString()) as Map;

    expect(result.remoteSnapshotComplete, false);
    expect(json['drafts'], hasLength(1));
    expect((json['errors'] as List).single['statusCode'], 429);
  });
}
