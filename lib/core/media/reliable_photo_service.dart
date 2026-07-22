import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/media/inspection_photo.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../data/local/operation_journal_repository.dart';
import 'image_processing_service.dart';

class ReliablePhotoService {
  ReliablePhotoService({ImageProcessingService? processor})
    : processor = processor ?? FlutterImageCompressProcessingService();
  final ImageProcessingService processor;
  bool _processing = false;

  Future<InspectionPhoto?> acquire({
    required ImageSource pickerSource,
    required String hydrantId,
    required String inspectionId,
    required String category,
    String inspectionType = 'f02A',
    String? testId,
    String? componentId,
    String? instrumentId,
    String? measurementSeriesId,
    String? measurementReadingId,
    String? evidenceRequirementId,
    required String userId,
    required String userName,
    required String brigadeId,
    required String deviceId,
  }) async {
    if (_processing) throw StateError('Ya se está procesando otra fotografía.');
    final picked = await ImagePicker().pickImage(source: pickerSource);
    if (picked == null) return null;
    _processing = true;
    File? temporary;
    OperationJournalEntry? operation;
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    try {
      final source = File(picked.path);
      if (!await source.exists() || await source.length() == 0) {
        throw StateError('El archivo está vacío o no existe.');
      }
      final header = await source
          .openRead(0, 12)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      final jpeg = header.length > 2 && header[0] == 0xff && header[1] == 0xd8;
      final png =
          header.length > 7 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4e &&
          header[3] == 0x47;
      if (!jpeg && !png) throw StateError('Formato de imagen no admitido.');
      final root = Directory(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'evidence',
          hydrantId,
          inspectionId,
        ),
      );
      await root.create(recursive: true);
      final id = const Uuid().v4();
      operation = OperationJournalEntry(
        operationId: const Uuid().v4(),
        operationType: JournalOperationType.capturePhoto,
        entityIds: [id, inspectionId],
        documentWrites: [id],
        fileWrites: ['$id.jpg', '${id}_thumb.jpg'],
        queueWrites: [id],
        preparedAt: DateTime.now().toUtc(),
        actor: userId,
        deviceId: deviceId,
        correlationId: id,
      );
      await journal.save(operation);
      temporary = File(p.join(root.path, '$id.tmp.jpg'));
      final processed = await processor.normalize(source, temporary.path);
      final finalFile = File(p.join(root.path, '$id.jpg'));
      await processed.file.open(mode: FileMode.append).then((handle) async {
        await handle.flush();
        await handle.close();
      });
      await processed.file.rename(finalFile.path);
      final finalBytes = await finalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(finalBytes);
      await codec.getNextFrame();
      codec.dispose();
      final thumbPath = p.join(root.path, '${id}_thumb.jpg');
      final thumb = await FlutterImageCompress.compressAndGetFile(
        finalFile.path,
        thumbPath,
        quality: 75,
        minWidth: 400,
        minHeight: 400,
        format: CompressFormat.jpeg,
      );
      if (thumb == null) throw StateError('No fue posible crear la miniatura.');
      final now = DateTime.now().toUtc();
      final photo = InspectionPhoto(
        id: id,
        hydrantId: hydrantId,
        inspectionId: inspectionId,
        inspectionType: inspectionType,
        category: category,
        testId: testId,
        componentId: componentId,
        instrumentId: instrumentId,
        measurementSeriesId: measurementSeriesId,
        measurementReadingId: measurementReadingId,
        evidenceRequirementId: evidenceRequirementId,
        source: pickerSource == ImageSource.camera
            ? PhotoSource.camera
            : PhotoSource.deviceLibrary,
        originalFilename: p.basename(source.path),
        normalizedFilename: p.basename(finalFile.path),
        localPath: finalFile.path,
        thumbnailPath: thumb.path,
        mimeType: 'image/jpeg',
        fileSize: finalBytes.length,
        width: processed.width,
        height: processed.height,
        sha256: sha256.convert(finalBytes).toString(),
        capturedAt: now,
        capturedByUserId: userId,
        capturedByName: userName,
        brigadeId: brigadeId,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      );
      final photos = Hive.box<String>('inspection_photos_v1');
      final queue = Hive.box<String>('media_work_queue_v1');
      await photos.put(id, jsonEncode(photo.toJson()));
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      await queue.put(id, 'pendingUpload');
      await journal.save(
        operation
            .advance(JournalStatus.queueWritten)
            .advance(JournalStatus.committed),
      );
      return photo;
    } on Object catch (error) {
      if (operation != null) {
        await journal.save(
          operation.advance(JournalStatus.needsRecovery, error: '$error'),
        );
      }
      rethrow;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      _processing = false;
    }
  }
}
