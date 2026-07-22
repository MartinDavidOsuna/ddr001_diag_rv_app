import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/media/inspection_photo.dart';
import '../../domain/media/media_sync_status.dart';

class SectionPhotoCounter extends StatelessWidget {
  const SectionPhotoCounter({
    required this.photos,
    required this.requiredEvidence,
    required this.onOpen,
    super.key,
  });

  final List<InspectionPhoto> photos;
  final bool requiredEvidence;
  final VoidCallback onOpen;

  bool _valid(InspectionPhoto photo) =>
      !photo.isDeleted &&
      File(photo.localPath).existsSync() &&
      photo.fileSize > 0 &&
      photo.sha256.isNotEmpty &&
      !const {
        MediaSyncStatus.failedRetryable,
        MediaSyncStatus.failedPermanent,
        MediaSyncStatus.missingLocal,
        MediaSyncStatus.remoteMissing,
      }.contains(photo.syncStatus);

  @override
  Widget build(BuildContext context) {
    final valid = photos.where(_valid).length;
    final processing = photos.any(
      (photo) => const {
        MediaSyncStatus.captured,
        MediaSyncStatus.validating,
        MediaSyncStatus.processing,
      }.contains(photo.syncStatus),
    );
    final invalid = photos.any((photo) => !_valid(photo) && !photo.isDeleted);
    final fulfilled = !requiredEvidence || valid > 0;
    final label = '$valid ${valid == 1 ? 'foto' : 'fotos'}';
    final detail = invalid
        ? 'Evidencia con error'
        : processing
        ? 'Procesando evidencia'
        : fulfilled
        ? 'Requisito cumplido'
        : 'Evidencia pendiente';
    final color = invalid
        ? AppColors.red
        : fulfilled
        ? AppColors.green
        : AppColors.orange;
    return Semantics(
      button: valid > 0,
      label: '$label. $detail',
      child: InkWell(
        onTap: valid > 0 ? onOpen : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                invalid
                    ? Icons.error_outline
                    : fulfilled
                    ? Icons.check_circle_outline
                    : Icons.photo_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('$label · $detail')),
              if (valid > 0) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
