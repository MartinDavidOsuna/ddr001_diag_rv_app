import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../domain/media/inspection_photo.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/media/photo_integrity_status.dart';
import 'thumbnail_regeneration_service.dart';

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
    for (final entry in photos.toMap().entries) {
      try {
        var photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (photo.isDeleted) continue;
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
            sync.get(photo.id) == MediaSyncStatus.verified.name;
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
          await sync.put(photo.id, MediaSyncStatus.verified.name);
          if (needsAdoption || !work.containsKey(photo.id)) {
            await work.put(
              photo.id,
              jsonEncode({
                'photoId': photo.id,
                'status': 'verify',
                'reconciledAt': now.toIso8601String(),
                'source': 'legacy-adoption',
              }),
            );
            actions.add('Confirmación legacy programada para verificación.');
          }
        } else if (!work.containsKey(photo.id)) {
          issues.add(MediaReconciliationIssue.missingQueue);
          await work.put(
            photo.id,
            jsonEncode({
              'photoId': photo.id,
              'status': exists ? 'pendingUpload' : 'missingLocal',
              'reconciledAt': DateTime.now().toUtc().toIso8601String(),
            }),
          );
          actions.add('Trabajo de medios recreado.');
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
}
