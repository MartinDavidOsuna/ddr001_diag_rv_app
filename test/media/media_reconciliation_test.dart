import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/data/local/media_reconciliation_service.dart';
import 'package:ddr001diag/data/local/media_work_item_codec.dart';
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
    expect(
      MediaWorkItemCodec.statusOf(
        value.id,
        Hive.box<String>('media_sync_queue').get(value.id),
      ),
      'verify',
    );
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
      final work = Hive.box<String>('media_work_queue_v1');
      final sync = Hive.box<String>('media_sync_queue');
      await box.put(missing.id, jsonEncode(missing.toJson()));
      await box.put(deleted.id, jsonEncode(deleted.toJson()));
      await work.put(deleted.id, 'discardedLocalInactiveDraft');
      await sync.put(deleted.id, 'discardedLocalInactiveDraft');

      final service = MediaReconciliationService();
      final result = await service.reconcile();

      expect(result.map((value) => value.photoId), ['photo-missing']);
      expect(
        result.single.issues,
        contains(MediaReconciliationIssue.missingOriginal),
      );
      expect(
        MediaWorkItemCodec.statusOf(missing.id, work.get(missing.id)),
        'missingLocal',
      );
      expect(box.containsKey(deleted.id), isTrue);
      expect(
        MediaWorkItemCodec.decode(
          deleted.id,
          work.get(deleted.id)!,
        ).schemaVersion,
        2,
      );
      expect(
        MediaWorkItemCodec.decode(
          deleted.id,
          sync.get(deleted.id)!,
        ).schemaVersion,
        2,
      );
      final workOnce = work.get(deleted.id);
      final syncOnce = sync.get(deleted.id);
      final workWrites = await writesDuring(work, service.reconcile);
      final syncWrites = await writesDuring(sync, service.reconcile);
      expect(workWrites, isEmpty);
      expect(syncWrites, isEmpty);
      expect(work.get(deleted.id), workOnce);
      expect(sync.get(deleted.id), syncOnce);
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
    await Hive.box<String>('media_work_queue_v1').put('legacy', 'verify');

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
    expect(
      MediaWorkItemCodec.decode(
        'legacy',
        Hive.box<String>('media_work_queue_v1').get('legacy')!,
      ).schemaVersion,
      2,
    );
  });

  test(
    '263 fotos reconciliadas no reescriben colas ni timestamps al reiniciar',
    () async {
      final photos = Hive.box<String>('inspection_photos_v1');
      final work = Hive.box<String>('media_work_queue_v1');
      final sync = Hive.box<String>('media_sync_queue');
      for (var index = 0; index < 263; index++) {
        final original = File('${files.path}/stable-$index.jpg')
          ..writeAsBytesSync([index % 251]);
        final thumbnail = File('${files.path}/stable-$index-thumb.jpg')
          ..writeAsBytesSync([index % 251]);
        final value = InspectionPhoto.fromJson({
          ...photo(
            id: 'stable-$index',
            original: original.path,
            thumbnail: thumbnail.path,
            status: MediaSyncStatus.verified,
          ).toJson(),
          'schemaVersion': 2,
        });
        await photos.put(value.id, jsonEncode(value.toJson()));
        final queueValue = jsonEncode({
          'schemaVersion': 2,
          'kind': 'mediaWorkItem',
          'photoId': value.id,
          'inspectionId': value.inspectionId,
          'slotCode': value.category,
          'status': 'verify',
          'legacyRaw': null,
          'updatedAt': '2026-08-01T00:00:00.000Z',
        });
        await work.put(value.id, queueValue);
        await sync.put(value.id, queueValue);
      }
      final workBefore = Map<Object, String>.from(work.toMap());
      final syncBefore = Map<Object, String>.from(sync.toMap());
      final service = MediaReconciliationService();

      late List<BoxEvent> syncWrites;
      late List<BoxEvent> workWrites;
      final photoWrites = await writesDuring(photos, () async {
        workWrites = await writesDuring(work, () async {
          syncWrites = await writesDuring(sync, service.reconcile);
        });
      });

      expect(photoWrites, isEmpty);
      expect(workWrites, isEmpty);
      expect(syncWrites, isEmpty);
      expect(work.toMap(), workBefore);
      expect(sync.toMap(), syncBefore);
    },
  );

  test('una confirmación nueva modifica sólo su foto y su cola', () async {
    final photos = Hive.box<String>('inspection_photos_v1');
    final work = Hive.box<String>('media_work_queue_v1');
    final sync = Hive.box<String>('media_sync_queue');
    for (var index = 0; index < 10; index++) {
      final original = File('${files.path}/incremental-$index.jpg')
        ..writeAsBytesSync([index]);
      final thumbnail = File('${files.path}/incremental-$index-thumb.jpg')
        ..writeAsBytesSync([index]);
      final value = InspectionPhoto.fromJson({
        ...photo(
          id: 'incremental-$index',
          original: original.path,
          thumbnail: thumbnail.path,
          status: index == 4
              ? MediaSyncStatus.uploadedUnverified
              : MediaSyncStatus.verified,
        ).toJson(),
        'schemaVersion': 2,
      });
      await photos.put(value.id, jsonEncode(value.toJson()));
      final stableQueue = MediaWorkItemCodec.pending(
        photoId: value.id,
        inspectionId: value.inspectionId,
        slotCode: value.category,
        status: 'verify',
      );
      await work.put(value.id, stableQueue);
      await sync.put(value.id, index == 4 ? 'verified' : stableQueue);
    }
    final untouchedPhotos = {
      for (var index = 0; index < 10; index++)
        if (index != 4) 'incremental-$index': photos.get('incremental-$index'),
    };
    final untouchedQueues = {
      for (var index = 0; index < 10; index++)
        if (index != 4) 'incremental-$index': sync.get('incremental-$index'),
    };

    late List<BoxEvent> syncWrites;
    late List<BoxEvent> workWrites;
    final photoWrites = await writesDuring(photos, () async {
      workWrites = await writesDuring(work, () async {
        syncWrites = await writesDuring(
          sync,
          MediaReconciliationService().reconcile,
        );
      });
    });

    expect(photoWrites.map((event) => event.key), ['incremental-4']);
    expect(workWrites, isEmpty);
    expect(syncWrites.map((event) => event.key), ['incremental-4']);
    for (final entry in untouchedPhotos.entries) {
      expect(photos.get(entry.key), entry.value);
    }
    for (final entry in untouchedQueues.entries) {
      expect(sync.get(entry.key), entry.value);
    }
    final changed = InspectionPhoto.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(photos.get('incremental-4')!) as Map,
      ),
    );
    expect(changed.syncStatus, MediaSyncStatus.verified);
    expect(changed.sha256, 'hash-incremental-4');
  });

  test('transición real conserva retry backoff error y lease', () async {
    final original = File('${files.path}/operational.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final thumbnail = File('${files.path}/operational-thumb.jpg')
      ..writeAsBytesSync([1]);
    final value = photo(
      id: 'operational-photo',
      original: original.path,
      thumbnail: thumbnail.path,
      status: MediaSyncStatus.verified,
    );
    final photos = Hive.box<String>('inspection_photos_v1');
    final work = Hive.box<String>('media_work_queue_v1');
    final sync = Hive.box<String>('media_sync_queue');
    await photos.put(value.id, jsonEncode(value.toJson()));
    final raw = jsonEncode({
      'schemaVersion': 2,
      'kind': 'mediaWorkItem',
      'photoId': value.id,
      'inspectionId': value.inspectionId,
      'slotCode': value.category,
      'status': 'pendingUpload',
      'attempts': 4,
      'nextRetryAt': '2026-08-30T00:00:00Z',
      'lastError': 'timeout',
      'leaseOwner': 'worker-a',
      'updatedAt': '2026-08-01T00:00:00Z',
    });
    await work.put(value.id, raw);
    await sync.put(value.id, raw);

    final writes = await writesDuring(
      sync,
      MediaReconciliationService().reconcile,
    );
    final reconciled = jsonDecode(sync.get(value.id)!) as Map;

    expect(writes.map((event) => event.key), [value.id]);
    expect(reconciled['status'], 'verify');
    expect(reconciled['attempts'], 4);
    expect(reconciled['nextRetryAt'], '2026-08-30T00:00:00Z');
    expect(reconciled['lastError'], 'timeout');
    expect(reconciled['leaseOwner'], 'worker-a');
  });
}
