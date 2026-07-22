import 'dart:io';

import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/media_sync_status.dart';
import 'package:ddr001diag/features/shared/section_photo_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photo_counter_');
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  InspectionPhoto photo(String id, String path, {DateTime? deletedAt}) {
    final now = DateTime.utc(2026, 7, 15);
    return InspectionPhoto(
      id: id,
      hydrantId: 'h-1',
      inspectionId: 'rv-1',
      category: 'daño',
      source: PhotoSource.camera,
      originalFilename: '$id.jpg',
      normalizedFilename: '$id.jpg',
      localPath: path,
      thumbnailPath: path,
      mimeType: 'image/jpeg',
      fileSize: 3,
      width: 10,
      height: 10,
      sha256: 'hash',
      capturedAt: now,
      capturedByUserId: 'user',
      capturedByName: 'Inspector',
      brigadeId: 'brigade',
      deviceId: 'device',
      syncStatus: MediaSyncStatus.pendingUpload,
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt,
    );
  }

  testWidgets('cuenta solo archivos válidos y abre la categoría', (tester) async {
    final validFile = File('${directory.path}/valid.jpg')..writeAsBytesSync([1, 2, 3]);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionPhotoCounter(
            photos: [
              photo('valid', validFile.path),
              photo('missing', '${directory.path}/missing.jpg'),
              photo('deleted', validFile.path, deletedAt: DateTime.utc(2026)),
            ],
            requiredEvidence: true,
            onOpen: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('1 foto'), findsOneWidget);
    expect(find.textContaining('Evidencia con error'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(opened, isTrue);
  });

  testWidgets('cero fotos comunica requisito pendiente y no abre', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionPhotoCounter(
            photos: const [],
            requiredEvidence: true,
            onOpen: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('0 fotos'), findsOneWidget);
    expect(find.textContaining('Evidencia pendiente'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(opened, isFalse);
  });
}
