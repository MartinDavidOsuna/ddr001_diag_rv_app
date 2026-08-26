import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/data/local/media_reconciliation_service.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;
  late Directory files;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    files = await Directory.systemTemp.createTemp('ddr001diag_media_');
  });
  tearDown(() async {
    if (files.existsSync()) files.deleteSync(recursive: true);
    await environment.close();
  });

  InspectionPhoto photo({
    required String id,
    required String original,
    required String thumbnail,
    MediaSyncStatus status = MediaSyncStatus.pendingUpload,
    DateTime? deletedAt,
  }) {
    final now = DateTime.utc(2026, 7, 15);
    return InspectionPhoto(
      id: id,
      hydrantId: 'h-1',
      inspectionId: 'rv-1',
      category: 'identificación',
      source: PhotoSource.camera,
      originalFilename: '$id.jpg',
      normalizedFilename: '$id.jpg',
      localPath: original,
      thumbnailPath: thumbnail,
      mimeType: 'image/jpeg',
      fileSize: 4,
      width: 10,
      height: 10,
      sha256: 'hash-$id',
      capturedAt: now,
      capturedByUserId: 'user',
      capturedByName: 'Inspector',
      brigadeId: 'brigade',
      deviceId: 'device',
      syncStatus: status,
      schemaVersion: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt,
    );
  }

  test(
    'recrea trabajo faltante sin verificar automáticamente la foto',
    () async {
      final original = File('${files.path}/original.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final thumbnail = File('${files.path}/thumb.jpg')
        ..writeAsBytesSync([1, 2]);
      final value = photo(
        id: 'photo-1',
        original: original.path,
        thumbnail: thumbnail.path,
      );
      await Hive.box<String>(
        'inspection_photos_v1',
      ).put(value.id, jsonEncode(value.toJson()));

      final result = await MediaReconciliationService().reconcile();

      expect(
        result.single.issues,
        contains(MediaReconciliationIssue.missingQueue),
      );
      final queued =
          jsonDecode(Hive.box<String>('media_work_queue_v1').get(value.id)!)
              as Map<String, dynamic>;
      expect(queued['status'], 'pendingUpload');
      expect(
        InspectionPhoto.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(Hive.box<String>('inspection_photos_v1').get(value.id)!)
                as Map,
          ),
        ).syncStatus,
        MediaSyncStatus.pendingUpload,
      );
    },
  );

  test('verified legacy se adopta sin asumir confirmación fuerte', () async {
    final original = File('${files.path}/original.jpg')..writeAsBytesSync([1]);
    final thumbnail = File('${files.path}/thumb.jpg')..writeAsBytesSync([1]);
    final value = photo(
      id: 'photo-2',
      original: original.path,
      thumbnail: thumbnail.path,
      status: MediaSyncStatus.uploadedUnverified,
    );
    await Hive.box<String>(
      'inspection_photos_v1',
    ).put(value.id, jsonEncode(value.toJson()));
    await Hive.box<String>('media_work_queue_v1').put(value.id, '{}');
    await Hive.box<String>('media_sync_queue').put(value.id, 'verified');

    final result = await MediaReconciliationService().reconcile();

    expect(
      result.single.issues,
      contains(MediaReconciliationIssue.inconsistentStatus),
    );
    expect(Hive.box<String>('media_sync_queue').get(value.id), 'verified');
    final repairedPhoto = InspectionPhoto.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(Hive.box<String>('inspection_photos_v1').get(value.id)!)
            as Map,
      ),
    );
    expect(repairedPhoto.syncStatus, MediaSyncStatus.verified);
    expect(
      repairedPhoto.integrityStatus,
      PhotoIntegrityStatus.serverConfirmationPending,
    );
    expect(repairedPhoto.schemaVersion, 2);
    final work = Map<String, dynamic>.from(
      jsonDecode(Hive.box<String>('media_work_queue_v1').get(value.id)!) as Map,
    );
    expect(work['status'], 'verify');
    expect(original.existsSync(), isTrue);
  });

  test('343 trabajos legacy no resucitan 226 confirmaciones remotas', () async {
    for (var index = 0; index < 343; index++) {
      final original = File('${files.path}/$index.jpg')..writeAsBytesSync([1]);
      final thumbnail = File('${files.path}/$index-thumb.jpg')
        ..writeAsBytesSync([1]);
      final value = photo(
        id: 'photo-$index',
        original: original.path,
        thumbnail: thumbnail.path,
      );
      await Hive.box<String>(
        'inspection_photos_v1',
      ).put(value.id, jsonEncode(value.toJson()));
      await Hive.box<String>(
        'media_work_queue_v1',
      ).put(value.id, 'pendingUpload');
      if (index < 226) {
        await Hive.box<String>('media_sync_queue').put(value.id, 'verified');
      }
    }

    final service = MediaReconciliationService();
    await service.reconcile();
    await service.reconcile(); // restart/idempotency

    var verifyWork = 0;
    var pendingWork = 0;
    for (final raw in Hive.box<String>('media_work_queue_v1').values) {
      final status = raw.startsWith('{')
          ? (jsonDecode(raw) as Map)['status']
          : raw;
      if (status == 'verify') verifyWork++;
      if (status == 'pendingUpload') pendingWork++;
    }
    expect(verifyWork, 226);
    expect(pendingWork, 117);
    expect(Hive.box<String>('inspection_photos_v1').length, 343);
  });

  test(
    'faltante se reporta y eliminado lógico se ignora sin borrar documento',
    () async {
      final missing = photo(
        id: 'photo-missing',
        original: '${files.path}/missing.jpg',
        thumbnail: '${files.path}/missing-thumb.jpg',
      );
      final deleted = photo(
        id: 'photo-deleted',
        original: '${files.path}/deleted.jpg',
        thumbnail: '${files.path}/deleted-thumb.jpg',
        deletedAt: DateTime.utc(2026, 7, 15),
      );
      final box = Hive.box<String>('inspection_photos_v1');
      await box.put(missing.id, jsonEncode(missing.toJson()));
      await box.put(deleted.id, jsonEncode(deleted.toJson()));

      final result = await MediaReconciliationService().reconcile();

      expect(result.map((value) => value.photoId), ['photo-missing']);
      expect(
        result.single.issues,
        contains(MediaReconciliationIssue.missingOriginal),
      );
      expect(box.containsKey(deleted.id), isTrue);
    },
  );

  test('migración schema 1 es aditiva e idempotente', () async {
    final original = File('${files.path}/legacy.jpg')..writeAsBytesSync([1]);
    final thumbnail = File('${files.path}/legacy-thumb.jpg')
      ..writeAsBytesSync([1]);
    final legacy =
        photo(
            id: 'legacy',
            original: original.path,
            thumbnail: thumbnail.path,
            status: MediaSyncStatus.verified,
          ).toJson()
          ..remove('integrityStatus')
          ..remove('mappingStatus')
          ..['schemaVersion'] = 1;
    final box = Hive.box<String>('inspection_photos_v1');
    await box.put('legacy', jsonEncode(legacy));
    await Hive.box<String>('media_sync_queue').put('legacy', 'verified');

    final service = MediaReconciliationService();
    await service.reconcile();
    final once = box.get('legacy');
    await service.reconcile();
    final twice = box.get('legacy');

    expect(twice, once);
    final migrated = InspectionPhoto.fromJson(
      Map<String, dynamic>.from(jsonDecode(twice!) as Map),
    );
    expect(migrated.schemaVersion, 2);
    expect(migrated.syncStatus, MediaSyncStatus.verified);
    expect(migrated.integrityStatus.isConfirmed, isFalse);
    expect(migrated.localPath, original.path);
    expect(migrated.sha256, 'hash-legacy');
    expect(original.existsSync(), isTrue);
  });
}
