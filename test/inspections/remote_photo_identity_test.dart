import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
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

  test('UUID remoto se compara sin sensibilidad a mayúsculas', () {
    const lower = 'f5de148d-1240-4cac-809c-1e655d0e85f7';
    const upper = 'F5DE148D-1240-4CAC-809C-1E655D0E85F7';
    final index = matchingRemotePhotoIndex(
      references: const [
        RvPhotoReference(
          photoId: lower,
          slotCode: 'back',
          status: RvPhotoUploadStatus.pending,
        ),
      ],
      remotePhoto: const RemotePhoto(
        id: upper,
        slotCode: 'back',
        status: 'verified',
      ),
      localPhoto: (_) => null,
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

  test(
    'confirmación persistida repara una referencia pendiente al reiniciar',
    () {
      final confirmed = InspectionPhoto.fromJson({
        ...photo('local-id', 'a' * 64).toJson(),
        'integrityStatus': PhotoIntegrityStatus.confirmed.name,
      });
      final reconciled = reconcileReferenceIntegrityTruth(
        references: const {
          'front_closed': [
            RvPhotoReference(
              photoId: 'local-id',
              serverPhotoId: 'SERVER-ID',
              slotCode: 'front_closed',
              status: RvPhotoUploadStatus.pending,
            ),
          ],
        },
        localPhoto: (_) => confirmed,
      );

      expect(
        reconciled['front_closed']!.single.status,
        RvPhotoUploadStatus.verified,
      );
      expect(reconciled['front_closed']!.single.serverPhotoId, 'SERVER-ID');
    },
  );
}
