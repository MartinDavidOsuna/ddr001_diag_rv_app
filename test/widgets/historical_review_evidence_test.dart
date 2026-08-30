import 'dart:convert';

import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/presentation/inspection_photo_projection.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'historial muestra miniaturas locales y permite abrir el original',
    (tester) async {
      final first = _photo('photo-1');
      final second = _photo('photo-2');
      final raw = {
        first.id: jsonEncode(first.toJson()),
        second.id: jsonEncode(second.toJson()),
      };
      final projection = InspectionPhotoDocumentProjection(
        readRaw: (id) => raw[id],
      );
      final references = [
        _reference(first.id, 'front_closed'),
        _reference(second.id, 'serial_plate'),
      ];
      String? openedPhotoId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RvHistoricalPhotoSummary(
              references: references,
              photoProjection: projection,
              thumbnailBuilder: (_, photo) => ColoredBox(
                key: ValueKey('thumbnail-${photo.id}'),
                color: Colors.blue,
              ),
              onOpenPhoto: (photo) => openedPhotoId = photo.id,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('FOTOGRAFÍAS DE EVIDENCIA (2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('historical-photo-photo-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('historical-photo-photo-2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('historical-photo-photo-1')));
      expect(openedPhotoId, 'photo-1');
      expect(find.text('FOTOGRAFÍAS DE EVIDENCIA (2)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

RvPhotoReference _reference(String photoId, String slot) => RvPhotoReference(
  photoId: photoId,
  slotCode: slot,
  status: RvPhotoUploadStatus.verified,
);

InspectionPhoto _photo(String id) {
  final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB');
  final now = DateTime.utc(2026, 8, 29);
  return InspectionPhoto(
    id: id,
    hydrantId: 'synthetic-hydrant',
    inspectionId: 'synthetic-history',
    category: 'evidence',
    source: PhotoSource.camera,
    originalFilename: '$id.png',
    normalizedFilename: '$id.png',
    localPath: '/synthetic/$id-original.png',
    thumbnailPath: '/synthetic/$id-thumbnail.png',
    mimeType: 'image/png',
    fileSize: bytes.length,
    width: 1,
    height: 1,
    sha256: 'a' * 64,
    capturedAt: now,
    capturedByUserId: 'synthetic-user',
    capturedByName: 'Synthetic User',
    brigadeId: 'synthetic-brigade',
    deviceId: 'synthetic-device',
    syncStatus: MediaSyncStatus.verified,
    integrityStatus: PhotoIntegrityStatus.confirmed,
    createdAt: now,
    updatedAt: now,
  );
}
