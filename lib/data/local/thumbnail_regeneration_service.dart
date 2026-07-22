import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/integrity/operation_journal.dart';
import '../../domain/media/inspection_photo.dart';
import 'operation_journal_repository.dart';

class ThumbnailRegenerationResult {
  const ThumbnailRegenerationResult({
    required this.photoId,
    required this.success,
    this.thumbnailPath,
    this.errorCode,
    this.errorMessage,
  });
  final String photoId;
  final bool success;
  final String? thumbnailPath, errorCode, errorMessage;
}

class ThumbnailRegenerationService {
  ThumbnailRegenerationService();

  static final Set<String> _activePhotoIds = <String>{};

  Future<ThumbnailRegenerationResult> regenerate(
    InspectionPhoto photo, {
    String actor = 'local-recovery',
    String deviceId = 'local-device',
  }) async {
    if (!_activePhotoIds.add(photo.id)) {
      return ThumbnailRegenerationResult(
        photoId: photo.id,
        success: false,
        errorCode: 'alreadyRunning',
        errorMessage: 'La miniatura ya se está regenerando.',
      );
    }
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    final targetPath = photo.thumbnailPath.isNotEmpty
        ? photo.thumbnailPath
        : p.join(p.dirname(photo.localPath), '${photo.id}_thumb.jpg');
    final temporaryPath = '$targetPath.${const Uuid().v4()}.tmp';
    var operation = OperationJournalEntry(
      operationId: const Uuid().v4(),
      operationType: JournalOperationType.capturePhoto,
      entityIds: [photo.id],
      documentWrites: [photo.id],
      fileWrites: [targetPath],
      preparedAt: DateTime.now().toUtc(),
      actor: actor,
      deviceId: deviceId,
      correlationId: 'thumbnail:${photo.id}',
    );
    await journal.save(operation);
    try {
      final original = File(photo.localPath);
      if (!await original.exists() || await original.length() == 0) {
        throw const FormatException('missingOriginal');
      }
      final generated = await FlutterImageCompress.compressAndGetFile(
        original.path,
        temporaryPath,
        quality: 75,
        minWidth: 400,
        minHeight: 400,
        format: CompressFormat.jpeg,
      );
      if (generated == null || !await File(generated.path).exists()) {
        throw const FormatException('imageDecodeFailed');
      }
      final target = File(targetPath);
      await target.parent.create(recursive: true);
      if (await target.exists()) await target.delete();
      await File(generated.path).rename(target.path);
      if (!await target.exists() || await target.length() == 0) {
        throw const FileSystemException('thumbnailWriteNotConfirmed');
      }
      operation = operation.advance(JournalStatus.filesWritten);
      await journal.save(operation);
      final box = Hive.box<String>('inspection_photos_v1');
      final raw = box.get(photo.id);
      if (raw == null) throw const FormatException('missingPhotoDocument');
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map)
        ..['thumbnailPath'] = target.path
        ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      await box.put(photo.id, jsonEncode(json));
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      await journal.save(operation.advance(JournalStatus.committed));
      await Hive.box<String>('trace_events').put(
        const Uuid().v4(),
        jsonEncode({
          'type': 'thumbnail_regenerated',
          'photoId': photo.id,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return ThumbnailRegenerationResult(
        photoId: photo.id,
        success: true,
        thumbnailPath: target.path,
      );
    } on Object catch (error) {
      final temporary = File(temporaryPath);
      if (await temporary.exists()) await temporary.delete();
      await journal.save(
        operation.advance(JournalStatus.needsRecovery, error: '$error'),
      );
      return ThumbnailRegenerationResult(
        photoId: photo.id,
        success: false,
        errorCode: '$error'.contains('imageDecodeFailed')
            ? 'corruptOriginal'
            : 'regenerationFailed',
        errorMessage: '$error',
      );
    } finally {
      _activePhotoIds.remove(photo.id);
    }
  }
}
