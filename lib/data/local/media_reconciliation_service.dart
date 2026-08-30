import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../domain/media/inspection_photo.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/media/photo_integrity_status.dart';
import 'thumbnail_regeneration_service.dart';
import 'media_work_item_codec.dart';

enum MediaReconciliationIssue {
  missingOriginal,
  missingThumbnail,
  missingQueue,
  inconsistentStatus,
  verifiedWithoutLocalFile,
  legacyConfirmationPending,
}

class MediaReconciliationResult {
  const MediaReconciliationResult({
    required this.photoId,
    required this.issues,
    required this.actions,
  });
  final String photoId;
  final List<MediaReconciliationIssue> issues;
  final List<String> actions;
}

class MediaReconciliationService {
  MediaReconciliationService({
    ThumbnailRegenerationService? thumbnailRegeneration,
    this.regenerateMissingThumbnails = false,
  }) : thumbnailRegeneration =
           thumbnailRegeneration ?? ThumbnailRegenerationService();

  final ThumbnailRegenerationService thumbnailRegeneration;
  final bool regenerateMissingThumbnails;

  Future<List<MediaReconciliationResult>> reconcile() async {
    final photos = Hive.box<String>('inspection_photos_v1');
    final work = Hive.box<String>('media_work_queue_v1');
    final sync = Hive.box<String>('media_sync_queue');
    final results = <MediaReconciliationResult>[];
    final photoIds = photos.keys.map((key) => '$key').toSet();
    for (final entry in work.toMap().entries) {
      final item = MediaWorkItemCodec.decode('${entry.key}', entry.value);
      if (item.schemaVersion < 2 && !photoIds.contains('${entry.key}')) {
        await work.put(entry.key, MediaWorkItemCodec.encode(item));
      }
    }
    for (final entry in sync.toMap().entries) {
      final item = MediaWorkItemCodec.decode('${entry.key}', entry.value);
      if (item.schemaVersion < 2 && !photoIds.contains('${entry.key}')) {
        await sync.put(entry.key, MediaWorkItemCodec.encode(item));
      }
    }
    for (final entry in photos.toMap().entries) {
      try {
        var photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (photo.isDeleted) {
          await _migrateLegacyQueueEntry(work, photo.id);
          await _migrateLegacyQueueEntry(sync, photo.id);
          continue;
        }
        final legacySchema = photo.schemaVersion < 2;
        if (legacySchema) {
          photo = InspectionPhoto.fromJson({
            ...photo.toJson(),
            'schemaVersion': 2,
            'integrityStatus':
                PhotoIntegrityStatus.serverConfirmationPending.name,
          });
          await photos.put(photo.id, jsonEncode(photo.toJson()));
        }
        final issues = <MediaReconciliationIssue>[];
        final actions = <String>[];
        final exists = File(photo.localPath).existsSync();
        final remotelyVerified =
            photo.syncStatus == MediaSyncStatus.verified ||
            MediaWorkItemCodec.statusOf(photo.id, sync.get(photo.id)) ==
                MediaSyncStatus.verified.name;
        if (!exists) {
          issues.add(MediaReconciliationIssue.missingOriginal);
          actions.add(
            'Marcada para revisión de archivo local; documento conservado.',
          );
        }
        if (photo.thumbnailPath.isEmpty ||
            !File(photo.thumbnailPath).existsSync()) {
          issues.add(MediaReconciliationIssue.missingThumbnail);
          if (exists && regenerateMissingThumbnails) {
            final regeneration = await thumbnailRegeneration.regenerate(photo);
            actions.add(
              regeneration.success
                  ? 'Miniatura regenerada y documento actualizado.'
                  : 'Miniatura no regenerada: ${regeneration.errorCode}.',
            );
          } else {
            actions.add(
              exists
                  ? 'Miniatura pendiente de reparación segura.'
                  : 'Miniatura no regenerable: falta el original.',
            );
          }
        }
        if (remotelyVerified) {
          final now = DateTime.now().toUtc();
          final needsAdoption = legacySchema;
          if (photo.syncStatus != MediaSyncStatus.verified || needsAdoption) {
            issues.add(MediaReconciliationIssue.inconsistentStatus);
            if (needsAdoption) {
              issues.add(MediaReconciliationIssue.legacyConfirmationPending);
            }
            final repaired = InspectionPhoto.fromJson({
              ...photo.toJson(),
              // Preserve the legacy value for rollback. Strong confirmation is
              // represented independently by integrityStatus.
              'syncStatus': MediaSyncStatus.verified.name,
              'integrityStatus':
                  PhotoIntegrityStatus.serverConfirmationPending.name,
              'schemaVersion': 2,
              'updatedAt': now.toIso8601String(),
              'lastError': null,
            });
            await photos.put(photo.id, jsonEncode(repaired.toJson()));
            actions.add('Documento local reconciliado a verified.');
          }
          await _putPendingIfChanged(
            sync,
            photoId: photo.id,
            inspectionId: photo.inspectionId,
            slotCode: photo.category,
            status: 'verify',
          );
          if (needsAdoption || !work.containsKey(photo.id)) {
            await _putPendingIfChanged(
              work,
              photoId: photo.id,
              inspectionId: photo.inspectionId,
              slotCode: photo.category,
              status: exists ? 'verify' : 'missingLocal',
            );
            actions.add('Confirmación legacy programada para verificación.');
          } else if (!exists) {
            await _putPendingIfChanged(
              work,
              photoId: photo.id,
              inspectionId: photo.inspectionId,
              slotCode: photo.category,
              status: 'missingLocal',
            );
          } else {
            await _migrateLegacyQueueEntry(work, photo.id);
          }
        } else if (!work.containsKey(photo.id)) {
          issues.add(MediaReconciliationIssue.missingQueue);
          await _putPendingIfChanged(
            work,
            photoId: photo.id,
            inspectionId: photo.inspectionId,
            slotCode: photo.category,
            status: exists ? 'pendingUpload' : 'missingLocal',
          );
          actions.add('Trabajo de medios recreado.');
        } else if (!exists) {
          await _putPendingIfChanged(
            work,
            photoId: photo.id,
            inspectionId: photo.inspectionId,
            slotCode: photo.category,
            status: 'missingLocal',
          );
          await _migrateLegacyQueueEntry(sync, photo.id);
        } else {
          await _migrateLegacyQueueEntry(work, photo.id);
          await _migrateLegacyQueueEntry(sync, photo.id);
        }
        if (photo.syncStatus == MediaSyncStatus.verified && !exists) {
          issues.add(MediaReconciliationIssue.verifiedWithoutLocalFile);
          actions.add(
            'Verified remoto conservado; falta local requiere revisión.',
          );
        }
        if (issues.isNotEmpty) {
          results.add(
            MediaReconciliationResult(
              photoId: photo.id,
              issues: issues,
              actions: actions,
            ),
          );
        }
      } on Object {
        // Corrupt documents are handled by QuarantineRepository.
      }
    }
    return results;
  }

  Future<void> _putPendingIfChanged(
    Box<String> box, {
    required String photoId,
    required String inspectionId,
    required String slotCode,
    required String status,
  }) async {
    final raw = box.get(photoId);
    final reconciled = MediaWorkItemCodec.reconcilePending(
      photoId,
      raw,
      photoId: photoId,
      inspectionId: inspectionId,
      slotCode: slotCode,
      status: status,
    );
    if (reconciled != null) await box.put(photoId, reconciled);
  }

  Future<void> _migrateLegacyQueueEntry(Box<String> box, String photoId) async {
    final raw = box.get(photoId);
    if (raw == null) return;
    final item = MediaWorkItemCodec.decode(photoId, raw);
    if (item.schemaVersion >= 2) return;
    await box.put(photoId, MediaWorkItemCodec.encode(item));
  }
}
