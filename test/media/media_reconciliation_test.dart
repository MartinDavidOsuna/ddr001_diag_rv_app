import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/data/local/media_reconciliation_service.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
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
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt,
    );
  }

  test('recrea trabajo faltante sin verificar automáticamente la foto', () async {
    final original = File('${files.path}/original.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    final thumbnail = File('${files.path}/thumb.jpg')..writeAsBytesSync([1, 2]);
    final value = photo(
      id: 'photo-1',
      original: original.path,
      thumbnail: thumbnail.path,
    );
    await Hive.box<String>('inspection_photos_v1').put(
      value.id,
      jsonEncode(value.toJson()),
    );

    final result = await MediaReconciliationService().reconcile();

    expect(result.single.issues, contains(MediaReconciliationIssue.missingQueue));
    final queued = jsonDecode(
      Hive.box<String>('media_work_queue_v1').get(value.id)!,
    ) as Map<String, dynamic>;
    expect(queued['status'], 'pendingUpload');
    expect(
      InspectionPhoto.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(Hive.box<String>('inspection_photos_v1').get(value.id)!) as Map,
        ),
      ).syncStatus,
      MediaSyncStatus.pendingUpload,
    );
  });

  test('uploadedUnverified no puede quedar verified en la cola', () async {
    final original = File('${files.path}/original.jpg')..writeAsBytesSync([1]);
    final thumbnail = File('${files.path}/thumb.jpg')..writeAsBytesSync([1]);
    final value = photo(
      id: 'photo-2',
      original: original.path,
      thumbnail: thumbnail.path,
      status: MediaSyncStatus.uploadedUnverified,
    );
    await Hive.box<String>('inspection_photos_v1').put(value.id, jsonEncode(value.toJson()));
    await Hive.box<String>('media_work_queue_v1').put(value.id, '{}');
    await Hive.box<String>('media_sync_queue').put(value.id, 'verified');

    final result = await MediaReconciliationService().reconcile();

    expect(result.single.issues, contains(MediaReconciliationIssue.inconsistentStatus));
    expect(Hive.box<String>('media_sync_queue').get(value.id), 'uploadedUnverified');
    expect(original.existsSync(), isTrue);
  });

  test('faltante se reporta y eliminado lógico se ignora sin borrar documento', () async {
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
    expect(result.single.issues, contains(MediaReconciliationIssue.missingOriginal));
    expect(box.containsKey(deleted.id), isTrue);
  });
}
