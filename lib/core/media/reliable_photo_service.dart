import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/media/inspection_photo.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../data/local/operation_journal_repository.dart';
import '../../data/local/media_work_item_codec.dart';
import 'image_processing_service.dart';
import 'file_digest_service.dart';

abstract interface class PhotoPicker {
  Future<XFile?> pickImage({
    required ImageSource source,
    String? captureId,
    String? durablePath,
  });
  Future<LostDataResponse> retrieveLostData();
  Future<DurableCameraOutcome> durableCameraOutcome(String captureId);
  Future<void> clearDurableCameraOutcome(String captureId);
}

enum DurableCameraOutcome { unknown, launched, success, canceled }

class PlatformPhotoPicker implements PhotoPicker {
  PlatformPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  static const _durableCamera = MethodChannel(
    'com.aquafim.ddr001diag/durable_camera',
  );

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    String? captureId,
    String? durablePath,
  }) async {
    if (source != ImageSource.camera) {
      return _picker.pickImage(source: source, requestFullMetadata: false);
    }
    if (captureId == null || durablePath == null) {
      throw StateError('La captura durable requiere identidad y destino.');
    }
    final path = await _durableCamera.invokeMethod<String>('capture', {
      'captureId': captureId,
      'path': durablePath,
    });
    return path == null ? null : XFile(path);
  }

  @override
  Future<LostDataResponse> retrieveLostData() => _picker.retrieveLostData();

  @override
  Future<DurableCameraOutcome> durableCameraOutcome(String captureId) async {
    final raw = await _durableCamera.invokeMethod<String>('status', {
      'captureId': captureId,
    });
    return DurableCameraOutcome.values
            .where((value) => value.name == raw)
            .firstOrNull ??
        DurableCameraOutcome.unknown;
  }

  @override
  Future<void> clearDurableCameraOutcome(String captureId) =>
      _durableCamera.invokeMethod<void>('clear', {'captureId': captureId});
}

abstract interface class PhotoThumbnailService {
  Future<File?> create(File source, String destination);
}

class FlutterPhotoThumbnailService implements PhotoThumbnailService {
  @override
  Future<File?> create(File source, String destination) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      source.path,
      destination,
      quality: 75,
      minWidth: 400,
      minHeight: 400,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
    );
    return result == null ? null : File(result.path);
  }
}

class ReliablePhotoService {
  ReliablePhotoService({
    ImageProcessingService? processor,
    FileDigestService? digestService,
    PhotoPicker? picker,
    PhotoThumbnailService? thumbnailService,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? supportDirectory,
  }) : processor = processor ?? FlutterImageCompressProcessingService(),
       digestService = digestService ?? const StreamingFileDigestService(),
       picker = picker ?? PlatformPhotoPicker(),
       thumbnailService = thumbnailService ?? FlutterPhotoThumbnailService(),
       documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final ImageProcessingService processor;
  final FileDigestService digestService;
  final PhotoPicker picker;
  final PhotoThumbnailService thumbnailService;
  final Future<Directory> Function() documentsDirectory;
  final Future<Directory> Function() supportDirectory;
  static bool _globalProcessing = false;
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
    String? localScopeNamespace,
  }) => _acquire(
    pickerSource: pickerSource,
    hydrantId: hydrantId,
    inspectionId: inspectionId,
    category: category,
    inspectionType: inspectionType,
    testId: testId,
    componentId: componentId,
    instrumentId: instrumentId,
    measurementSeriesId: measurementSeriesId,
    measurementReadingId: measurementReadingId,
    evidenceRequirementId: evidenceRequirementId,
    userId: userId,
    userName: userName,
    brigadeId: brigadeId,
    deviceId: deviceId,
    localScopeNamespace: localScopeNamespace,
    allowNewCapture: true,
  );

  /// Recovers every durable camera attempt owned by this inspection/scope.
  /// A new service instance is intentionally sufficient: no in-memory state
  /// from the process that launched the external camera is required.
  Future<List<InspectionPhoto>> recoverPendingForInspection({
    required String inspectionId,
    required String userId,
    required String userName,
    required String brigadeId,
    required String deviceId,
    String? localScopeNamespace,
  }) async {
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    final candidates = journal.pending().where((entry) {
      final ids = entry.entityIds;
      return entry.operationType == JournalOperationType.capturePhoto &&
          ids.length >= 5 &&
          _recoverableMarker(ids.first) &&
          ImageSource.values.any((source) => source.name == ids[4]) &&
          ids[1].toLowerCase() == inspectionId.toLowerCase() &&
          entry.actor.toLowerCase() == userId.toLowerCase() &&
          entry.deviceId.toLowerCase() == deviceId.toLowerCase() &&
          _scopeMatches(ids, localScopeNamespace);
    }).toList()..sort((a, b) => a.preparedAt.compareTo(b.preparedAt));
    final recovered = <InspectionPhoto>[];
    for (final entry in candidates) {
      final ids = entry.entityIds;
      final pickerSource = ImageSource.values.byName(ids[4]);
      final photo = await _acquire(
        pickerSource: pickerSource,
        hydrantId: ids[2],
        inspectionId: ids[1],
        category: ids[3],
        inspectionType: _journalValue(ids, 8, fallback: 'f02A'),
        testId: _journalNullable(ids, 9),
        componentId: _journalNullable(ids, 10),
        instrumentId: _journalNullable(ids, 11),
        measurementSeriesId: _journalNullable(ids, 12),
        measurementReadingId: _journalNullable(ids, 13),
        evidenceRequirementId: _journalNullable(ids, 14),
        userId: userId,
        userName: ids.length > 5 && ids[5].isNotEmpty ? ids[5] : userName,
        brigadeId: ids.length > 6 && ids[6].isNotEmpty ? ids[6] : brigadeId,
        deviceId: deviceId,
        localScopeNamespace: localScopeNamespace,
        allowNewCapture: false,
        requiredOperationId: entry.operationId,
      );
      if (photo != null) recovered.add(photo);
    }
    return recovered;
  }

  Future<InspectionPhoto?> _acquire({
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
    String? localScopeNamespace,
    required bool allowNewCapture,
    String? requiredOperationId,
  }) async {
    if (_processing || _globalProcessing) {
      throw StateError('Ya se está procesando otra fotografía.');
    }
    _processing = true;
    _globalProcessing = true;
    final totalWatch = Stopwatch()..start();
    File? temporary;
    OperationJournalEntry? operation;
    late final OperationJournalRepository journal;
    try {
      journal = OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      );
      final root = Directory(
        p.join(
          (await documentsDirectory()).path,
          'evidence',
          hydrantId,
          inspectionId,
        ),
      );
      await root.create(recursive: true);
      XFile? picked;
      final recoverable = journal.pending().where((entry) {
        final ids = entry.entityIds;
        return entry.operationType == JournalOperationType.capturePhoto &&
            ids.length >= 5 &&
            _recoverableMarker(ids[0]) &&
            ids[1].toLowerCase() == inspectionId.toLowerCase() &&
            ids[2].toLowerCase() == hydrantId.toLowerCase() &&
            ids[3] == category &&
            ids[4] == pickerSource.name &&
            entry.actor.toLowerCase() == userId.toLowerCase() &&
            entry.deviceId.toLowerCase() == deviceId.toLowerCase() &&
            _scopeMatches(ids, localScopeNamespace) &&
            (requiredOperationId == null ||
                entry.operationId == requiredOperationId);
      }).toList()..sort((a, b) => b.preparedAt.compareTo(a.preparedAt));
      if (recoverable.isNotEmpty) {
        operation = recoverable.first;
        final stored = await _storedPhoto(operation.operationId);
        if (stored != null) return stored;
        final durable = await _validatedDurableSource(operation);
        if (operation.entityIds.first == 'camera-pending-v2') {
          final outcome = await picker.durableCameraOutcome(
            operation.operationId,
          );
          if (outcome == DurableCameraOutcome.canceled) {
            await journal.save(operation.advance(JournalStatus.committed));
            await picker.clearDurableCameraOutcome(operation.operationId);
            return null;
          }
          if (outcome == DurableCameraOutcome.success) {
            if (durable == null || !await _validSource(durable)) {
              throw StateError(
                'La cámara confirmó la captura pero el archivo durable no está disponible.',
              );
            }
            picked = XFile(durable.path);
          } else {
            // The camera may still own the destination. Preserve the journal
            // even if bytes are already visible; only RESULT_OK proves that
            // the external writer finished its transaction.
            return null;
          }
        } else {
          final lost = await picker.retrieveLostData();
          if (lost.exception != null) {
            throw StateError(
              'La cámara no pudo restaurar la captura pendiente.',
            );
          }
          picked = lost.file ?? lost.files?.lastOrNull;
          if (picked == null) return null;
        }
      }
      if (picked == null && !allowNewCapture) return null;
      if (picked == null) {
        final id = const Uuid().v4();
        final staging = Directory(
          p.join((await supportDirectory()).path, 'camera-capture-staging'),
        );
        await staging.create(recursive: true);
        final durablePath = p.join(staging.path, '$id.source.jpg');
        operation = OperationJournalEntry(
          operationId: id,
          operationType: JournalOperationType.capturePhoto,
          entityIds: [
            pickerSource == ImageSource.camera
                ? 'camera-pending-v2'
                : 'picker-pending-v1',
            inspectionId,
            hydrantId,
            category,
            pickerSource.name,
            userName,
            brigadeId,
            localScopeNamespace ?? '',
            inspectionType,
            testId ?? '',
            componentId ?? '',
            instrumentId ?? '',
            measurementSeriesId ?? '',
            measurementReadingId ?? '',
            evidenceRequirementId ?? '',
          ],
          documentWrites: [id],
          fileWrites: [
            p.join(root.path, '$id.jpg'),
            p.join(root.path, '${id}_thumb.jpg'),
            if (pickerSource == ImageSource.camera) durablePath,
          ],
          queueWrites: [id],
          preparedAt: DateTime.now().toUtc(),
          actor: userId,
          deviceId: deviceId,
          correlationId: id,
        );
        await journal.save(operation);
        final pickerWatch = Stopwatch()..start();
        picked = await picker.pickImage(
          source: pickerSource,
          captureId: id,
          durablePath: pickerSource == ImageSource.camera ? durablePath : null,
        );
        _perf('picker_return_ms', pickerWatch.elapsedMilliseconds);
        if (picked == null) {
          await journal.save(operation.advance(JournalStatus.committed));
          if (pickerSource == ImageSource.camera) {
            await picker.clearDurableCameraOutcome(id);
          }
          final durable = File(durablePath);
          if (await durable.exists()) await durable.delete();
          return null;
        }
      }
      final id = operation!.operationId;
      final source = File(picked.path);
      if (!await _validSource(source)) {
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
      // Digest camera-returned bytes before normalization. This remains
      // streaming and does not retain another full-resolution buffer.
      final receivedDigest = await digestService.sha256Of(source);
      final receivedLength = await source.length();
      temporary = File(p.join(root.path, '$id.tmp.jpg'));
      final normalizeWatch = Stopwatch()..start();
      final processed = await processor.normalize(source, temporary.path);
      _perf('normalize_ms', normalizeWatch.elapsedMilliseconds);
      if (!await source.exists() ||
          await source.length() != receivedLength ||
          await digestService.sha256Of(source) != receivedDigest) {
        throw StateError('La fuente cambió durante el procesamiento.');
      }
      final finalFile = File(p.join(root.path, '$id.jpg'));
      await processed.file.open(mode: FileMode.append).then((handle) async {
        await handle.flush();
        await handle.close();
      });
      await processed.file.rename(finalFile.path);
      final validationWatch = Stopwatch()..start();
      final fileSize = await finalFile.length();
      if (fileSize <= 0 || processed.width < 640 || processed.height < 480) {
        throw StateError('La fotografía normalizada no es válida.');
      }
      _perf('validate_ms', validationWatch.elapsedMilliseconds);
      final thumbPath = p.join(root.path, '${id}_thumb.jpg');
      final thumbnailWatch = Stopwatch()..start();
      final thumb = await thumbnailService.create(finalFile, thumbPath);
      if (thumb == null) throw StateError('No fue posible crear la miniatura.');
      _perf('thumbnail_ms', thumbnailWatch.elapsedMilliseconds);
      final hashWatch = Stopwatch()..start();
      // The digest consumes file chunks and never retains a full JPEG buffer.
      final digest = await digestService.sha256Of(finalFile);
      _perf('hash_ms', hashWatch.elapsedMilliseconds);
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
        fileSize: fileSize,
        width: processed.width,
        height: processed.height,
        sha256: digest,
        receivedSha256: receivedDigest,
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
      final persistWatch = Stopwatch()..start();
      await photos.put(id, jsonEncode(photo.toJson()));
      operation = operation.advance(JournalStatus.photoSaved);
      await journal.save(operation);
      // Queueing before the draft link is safe, but the journal deliberately
      // remains incomplete until linkPhotoToDraft commits the whole operation.
      await queue.put(
        id,
        MediaWorkItemCodec.pending(
          photoId: id,
          inspectionId: inspectionId,
          slotCode: category,
        ),
      );
      _perf('persist_ms', persistWatch.elapsedMilliseconds);
      _perf('total_ms', totalWatch.elapsedMilliseconds);
      return photo;
    } on Object catch (error) {
      if (operation != null) {
        await journal.save(
          operation.advance(
            JournalStatus.needsRecovery,
            error: error.runtimeType.toString(),
          ),
        );
      }
      rethrow;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      _processing = false;
      _globalProcessing = false;
    }
  }

  Future<void> markDraftLinkedAndCommitted(String photoId) async {
    final repository = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    final entry = repository.find(photoId);
    if (entry == null) return;
    if (entry.status != JournalStatus.committed) {
      final photo = await _storedPhoto(photoId);
      if (photo == null) {
        throw StateError(
          'No se puede confirmar una captura sin archivo íntegro.',
        );
      }
      final queue = Hive.box<String>('media_work_queue_v1');
      if (!queue.containsKey(photoId)) {
        await queue.put(
          photoId,
          MediaWorkItemCodec.pending(
            photoId: photoId,
            inspectionId: photo.inspectionId,
            slotCode: photo.category,
          ),
        );
      }
      final linked = entry.advance(JournalStatus.draftLinked);
      await repository.save(linked);
      await repository.save(
        linked
            .advance(JournalStatus.queueWritten)
            .advance(JournalStatus.committed),
      );
    }
    await _cleanupCommittedSource(entry);
  }

  Future<void> cleanupCommittedCaptureSources() async {
    final box = Hive.box<String>('operation_journal_v1');
    for (final raw in box.values) {
      try {
        final entry = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (entry.operationType == JournalOperationType.capturePhoto &&
            entry.status == JournalStatus.committed) {
          await _cleanupCommittedSource(entry);
        }
      } on Object {
        // An unreadable journal is preserved for the integrity auditor.
      }
    }
  }

  Future<void> _cleanupCommittedSource(OperationJournalEntry entry) async {
    final source = await _validatedDurableSource(entry);
    if (source != null && await source.exists()) await source.delete();
    if (entry.entityIds.firstOrNull == 'camera-pending-v2') {
      await picker.clearDurableCameraOutcome(entry.operationId);
    }
  }

  Future<InspectionPhoto?> _storedPhoto(String id) async {
    final raw = Hive.box<String>('inspection_photos_v1').get(id);
    if (raw == null) return null;
    try {
      final photo = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final file = File(photo.localPath);
      if (!await file.exists() || await file.length() != photo.fileSize) {
        return null;
      }
      return await digestService.sha256Of(file) == photo.sha256 ? photo : null;
    } on Object {
      return null;
    }
  }

  Future<File?> _validatedDurableSource(OperationJournalEntry entry) async {
    if (entry.entityIds.firstOrNull != 'camera-pending-v2' ||
        !_captureIdPattern.hasMatch(entry.operationId)) {
      return null;
    }
    final staging = Directory(
      p.join((await supportDirectory()).path, 'camera-capture-staging'),
    );
    final expected = File(
      p.join(staging.path, '${entry.operationId}.source.jpg'),
    );
    final expectedPath = p.normalize(p.absolute(expected.path));
    final stored = entry.fileWrites
        .where((path) => p.normalize(p.absolute(path)) == expectedPath)
        .firstOrNull;
    if (stored == null) return null;
    final candidate = File(stored);
    if (await candidate.exists()) {
      await staging.create(recursive: true);
      final stagingCanonical = await staging.resolveSymbolicLinks();
      final candidateCanonical = await candidate.resolveSymbolicLinks();
      if (p.dirname(candidateCanonical) != stagingCanonical) return null;
    }
    return candidate;
  }

  Future<bool> _validSource(File source) async {
    if (!await source.exists()) return false;
    final first = await source.length();
    if (first <= 0) return false;
    // The camera may have returned before its writer closed the descriptor.
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return await source.exists() && await source.length() == first;
  }

  bool _scopeMatches(List<String> ids, String? namespace) {
    if (ids.firstOrNull != 'camera-pending-v2' &&
        ids.firstOrNull != 'picker-pending-v1') {
      return true;
    }
    final stored = ids.length > 7 ? ids[7] : '';
    return stored.toLowerCase() == (namespace ?? '').toLowerCase();
  }

  bool _recoverableMarker(String value) => const {
    'camera-pending-v1',
    'camera-pending-v2',
    'picker-pending-v1',
  }.contains(value);

  String _journalValue(
    List<String> values,
    int index, {
    required String fallback,
  }) => index < values.length && values[index].isNotEmpty
      ? values[index]
      : fallback;

  String? _journalNullable(List<String> values, int index) =>
      index < values.length && values[index].isNotEmpty ? values[index] : null;

  static final _captureIdPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  void _perf(String metric, int milliseconds) {
    if (kDebugMode || kProfileMode) {
      debugPrint('[PERF][PHOTO] $metric=$milliseconds');
    }
  }
}
