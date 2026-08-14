import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 13);
  InspectionPhoto photo(String id, String hash) => InspectionPhoto(
    id: id,
    hydrantId: 'hydrant',
    inspectionId: 'inspection',
    category: 'front_closed',
    source: PhotoSource.camera,
    originalFilename: '$id.jpg',
    normalizedFilename: '$id.jpg',
    localPath: '/preserved/$id.jpg',
    thumbnailPath: '/preserved/$id-thumb.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1,
    width: 1,
    height: 1,
    sha256: hash,
    capturedAt: now,
    capturedByUserId: 'user',
    capturedByName: 'Inspector',
    brigadeId: 'crew',
    deviceId: 'device',
    createdAt: now,
    updatedAt: now,
  );

  test('reconcilia ID remoto distinto mediante slot y client sha256', () {
    final references = [
      const RvPhotoReference(
        photoId: 'local-id',
        slotCode: 'front_closed',
        status: RvPhotoUploadStatus.error,
      ),
    ];
    final local = photo('local-id', 'a' * 64);
    final index = matchingRemotePhotoIndex(
      references: references,
      remotePhoto: RemotePhoto(
        id: 'server-id',
        slotCode: 'front_closed',
        status: 'verified',
        clientSha256: 'a' * 64,
        sha256: 'b' * 64,
      ),
      localPhoto: (_) => local,
    );
    expect(index, 0);
  });

  test('hash ambiguo no crea falso positivo', () {
    final references = [
      for (final id in ['one', 'two'])
        RvPhotoReference(
          photoId: id,
          slotCode: 'front_closed',
          status: RvPhotoUploadStatus.pending,
        ),
    ];
    expect(
      matchingRemotePhotoIndex(
        references: references,
        remotePhoto: RemotePhoto(
          id: 'server-id',
          slotCode: 'front_closed',
          status: 'verified',
          clientSha256: 'a' * 64,
        ),
        localPhoto: (id) => photo(id, 'a' * 64),
      ),
      -1,
    );
  });
}
