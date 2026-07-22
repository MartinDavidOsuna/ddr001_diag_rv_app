import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../domain/media/inspection_photo.dart';
import '../../domain/media/media_sync_status.dart';
import 'thumbnail_regeneration_service.dart';

enum MediaReconciliationIssue {
  missingOriginal,
  missingThumbnail,
  missingQueue,
  inconsistentStatus,
  verifiedWithoutLocalFile,
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
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (photo.isDeleted) continue;
        final issues = <MediaReconciliationIssue>[];
        final actions = <String>[];
        final exists = File(photo.localPath).existsSync();
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
        if (!work.containsKey(photo.id)) {
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
        if (photo.syncStatus == MediaSyncStatus.uploadedUnverified &&
            sync.get(photo.id) == MediaSyncStatus.verified.name) {
          issues.add(MediaReconciliationIssue.inconsistentStatus);
          await sync.put(photo.id, MediaSyncStatus.uploadedUnverified.name);
          actions.add('Estado restaurado a uploadedUnverified.');
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
