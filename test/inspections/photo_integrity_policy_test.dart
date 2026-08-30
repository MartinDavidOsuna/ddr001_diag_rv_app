import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RemotePhotoIntegrity result(
    PhotoIntegrityStatus status, {
    bool retryable = true,
    bool repairable = true,
  }) => RemotePhotoIntegrity(
    photoId: 'photo-1',
    status: status,
    originalPresent: status != PhotoIntegrityStatus.missingOriginal,
    thumbnailPresent: status != PhotoIntegrityStatus.missingThumbnail,
    storageVerified: true,
    mapped: status != PhotoIntegrityStatus.missingMapping,
    mappingStatus: status == PhotoIntegrityStatus.missingMapping
        ? PhotoMappingStatus.missing
        : status == PhotoIntegrityStatus.mappingConflict
        ? PhotoMappingStatus.conflict
        : PhotoMappingStatus.mapped,
    retryable: retryable,
    repairable: repairable,
  );

  test('reupload se limita a evidencia recuperable con bytes locales', () {
    expect(
      shouldReuploadForIntegrity(result(PhotoIntegrityStatus.missingOriginal)),
      isTrue,
    );
    expect(
      shouldReuploadForIntegrity(result(PhotoIntegrityStatus.hashMismatch)),
      isTrue,
    );
    expect(
      shouldReuploadForIntegrity(
        result(PhotoIntegrityStatus.notFound, retryable: false),
      ),
      isTrue,
    );
  });

  test('thumbnail y mapping nunca provocan reupload', () {
    expect(
      shouldReuploadForIntegrity(result(PhotoIntegrityStatus.missingThumbnail)),
      isFalse,
    );
    expect(
      shouldReuploadForIntegrity(result(PhotoIntegrityStatus.missingMapping)),
      isFalse,
    );
    expect(
      shouldReuploadForIntegrity(
        result(
          PhotoIntegrityStatus.mappingConflict,
          retryable: false,
          repairable: false,
        ),
      ),
      isFalse,
    );
    expect(
      shouldReuploadForIntegrity(
        result(
          PhotoIntegrityStatus.deleted,
          retryable: false,
          repairable: false,
        ),
      ),
      isFalse,
    );
  });

  test('7/9 no sincroniza y 9/9 confirmadas sí', () {
    expect(
      isEvidenceFullyConfirmed([
        ...List.filled(7, PhotoIntegrityStatus.confirmed),
        ...List.filled(2, PhotoIntegrityStatus.serverConfirmationPending),
      ]),
      isFalse,
    );
    expect(
      isEvidenceFullyConfirmed(List.filled(9, PhotoIntegrityStatus.confirmed)),
      isTrue,
    );
  });
}
