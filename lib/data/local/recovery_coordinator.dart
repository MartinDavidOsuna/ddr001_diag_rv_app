import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../core/security/f02a_scoped_identity.dart';
import '../../domain/integrity/integrity_models.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../domain/media/inspection_photo.dart';
import 'integrity_audit_service.dart';
import 'media_work_item_codec.dart';
import 'operation_journal_repository.dart';
import 'quarantine_repository.dart';
import 'thumbnail_regeneration_service.dart';

class RecoverySummary {
  const RecoverySummary({
    required this.audit,
    required this.repaired,
    required this.quarantined,
    required this.requiresManualReview,
  });
  final IntegrityAuditReport audit;
  final int repaired, quarantined, requiresManualReview;
}

class RecoveryCoordinator {
  const RecoveryCoordinator({
    required this.auditService,
    required this.journal,
    required this.quarantine,
  });
  final IntegrityAuditService auditService;
  final OperationJournalRepository journal;
  final QuarantineRepository quarantine;

  Future<RecoverySummary> runLightweight({
    bool includeMediaRepair = false,
  }) async {
    final report = auditService.runLightweight();
    var repaired = 0, quarantined = 0, manual = 0;
    for (final issue in report.issues) {
      switch (issue.recommendedAction) {
        case RecoveryAction.recreateIndex:
          final box = issue.entityType == 'visualInspection'
              ? Hive.box<String>('active_inspection_index_v1')
              : Hive.box<String>('active_functional_inspection_index_v1');
          final documents = issue.entityType == 'visualInspection'
              ? Hive.box<String>('visual_inspections_v1')
              : Hive.box<String>('functional_inspections_v1');
          final raw = documents.get(issue.entityId);
          if (raw != null) {
            final payload = VersionedJsonCodec.decode(raw).payload;
            final hydrantId = payload['hydrantId'] as String?;
            if (hydrantId != null) {
              await box.put(
                _activeIndexKey(
                  payload,
                  hydrantId,
                  issue.entityType == 'visualInspection' ? 'f02A' : 'f02B',
                ),
                issue.entityId,
              );
              repaired++;
            }
          }
        case RecoveryAction.removeOrphanIndex:
          final box = issue.entityType == 'visualInspection'
              ? Hive.box<String>('active_inspection_index_v1')
              : Hive.box<String>('active_functional_inspection_index_v1');
          final keys = box.keys.where((key) => box.get(key) == issue.entityId);
          for (final key in keys.toList()) {
            await box.delete(key);
          }
          repaired++;
        case RecoveryAction.enqueuePhoto:
          await Hive.box<String>('media_work_queue_v1').put(
            issue.entityId,
            jsonEncode({
              'photoId': issue.entityId,
              'status': 'pendingRecovery',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            }),
          );
          repaired++;
        case RecoveryAction.regenerateThumbnail:
          if (!includeMediaRepair) {
            manual++;
            break;
          }
          final raw = Hive.box<String>(
            'inspection_photos_v1',
          ).get(issue.entityId);
          if (raw == null) {
            manual++;
            break;
          }
          try {
            final photo = InspectionPhoto.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
            final result = await ThumbnailRegenerationService().regenerate(
              photo,
            );
            result.success ? repaired++ : manual++;
          } on Object {
            manual++;
          }
        case RecoveryAction.quarantineDocument:
          final box = Hive.box<String>(issue.entityType);
          final raw = box.get(issue.entityId);
          if (raw != null) {
            await quarantine.preserve(
              sourceBox: issue.entityType,
              sourceKey: issue.entityId,
              originalDocument: raw,
              errorType: issue.type.name,
              technicalMessage: issue.technicalMessage,
            );
            quarantined++;
          }
        default:
          manual++;
      }
    }
    for (final entry in journal.pending()) {
      final result = await recoverJournalEntry(entry);
      if (result == JournalRecoveryOutcome.committed ||
          result == JournalRecoveryOutcome.safelyCompensated) {
        repaired++;
      } else if (result == JournalRecoveryOutcome.quarantined) {
        quarantined++;
      } else {
        manual++;
      }
    }
    return RecoverySummary(
      audit: report,
      repaired: repaired,
      quarantined: quarantined,
      requiresManualReview: manual,
    );
  }

  String _activeIndexKey(
    Map<String, dynamic> payload,
    String hydrantId,
    String reportType,
  ) {
    // Preserve the byte-compatible F02B/Levantamientos index contract.
    if (reportType != 'f02A') return '$hydrantId:$reportType';
    final rawScope = payload['dataScope'];
    if (rawScope is Map) {
      final scope = Map<String, dynamic>.from(rawScope);
      final scopedKey = buildF02AScopedKey(
        environment: scope['environment']?.toString(),
        accountId: scope['accountId']?.toString(),
        ownerUserId: scope['ownerUserId']?.toString(),
        createdBy: payload['createdBy']?.toString(),
        inspectorId: payload['inspectorId']?.toString(),
        hydrantId: hydrantId,
      );
      if (scopedKey != null) return scopedKey;
    }
    return '$hydrantId:$reportType';
  }

  Future<JournalRecoveryOutcome> recoverJournalEntry(
    OperationJournalEntry entry,
  ) async {
    if (entry.status == JournalStatus.committed) {
      return JournalRecoveryOutcome.committed;
    }
    if (entry.status == JournalStatus.quarantined) {
      return JournalRecoveryOutcome.quarantined;
    }
    if (entry.operationType ==
        JournalOperationType.discardInactiveClosureDraft) {
      return _recoverInactiveClosureDraftDiscard(entry);
    }
    if (entry.operationType == JournalOperationType.saveInactiveClosureDraft) {
      return _recoverInactiveClosureDraftSave(entry);
    }
    if (entry.status == JournalStatus.prepared) {
      if (_isPendingExternalCamera(entry)) {
        return _markManual(entry, pendingExternalCameraRecoveryError);
      }
      final hasObservableWrites =
          _anyDocumentExists(entry) ||
          entry.fileWrites.any((path) => File(path).existsSync()) ||
          _anyQueueExists(entry);
      if (!hasObservableWrites) {
        await journal.save(
          entry.advance(
            JournalStatus.failed,
            error:
                'Operación preparada sin escrituras observables; no se inventaron datos.',
          ),
        );
        return JournalRecoveryOutcome.safelyCompensated;
      }
      return _markManual(
        entry,
        'Fase prepared con escrituras parciales ambiguas.',
      );
    }
    if (entry.status == JournalStatus.queueWritten) {
      if (_queuesExist(entry) && _documentsExist(entry)) {
        await journal.save(entry.advance(JournalStatus.committed));
        return JournalRecoveryOutcome.committed;
      }
      return _markManual(
        entry,
        'queueWritten sin documentos o colas confirmables.',
      );
    }
    if (entry.operationType == JournalOperationType.capturePhoto) {
      return _recoverPhotoOperation(entry);
    }
    if (entry.status == JournalStatus.documentsWritten ||
        entry.status == JournalStatus.indexesWritten) {
      final indexRepaired = await _repairReportIndex(entry);
      if (indexRepaired && entry.queueWrites.isEmpty) {
        await journal.save(entry.advance(JournalStatus.committed));
        return JournalRecoveryOutcome.committed;
      }
      return _markManual(
        entry,
        'Documentos conservados; faltan fases que no pueden inferirse con certeza.',
      );
    }
    if (entry.status == JournalStatus.filesWritten) {
      return _markManual(
        entry,
        'Archivos conservados; falta relación documental inequívoca.',
      );
    }
    return _markManual(
      entry,
      'Estado ${entry.status.name} requiere revisión; no se aplicó borrado ni creación.',
    );
  }

  Future<JournalRecoveryOutcome> _recoverInactiveClosureDraftSave(
    OperationJournalEntry entry,
  ) async {
    final inspectionId = entry.entityIds.firstOrNull;
    final raw = inspectionId == null
        ? null
        : Hive.box<String>('visual_inspections_v1').get(inspectionId);
    if (raw == null) {
      await journal.save(
        entry.advance(
          JournalStatus.failed,
          error: 'No se observó el documento del borrador inactivo.',
        ),
      );
      return JournalRecoveryOutcome.safelyCompensated;
    }
    try {
      final embedded = VersionedJsonCodec.decode(raw).payload['rvDynamicDraft'];
      final draft = embedded is Map ? embedded['inactiveClosureDraft'] : null;
      if (draft is Map && draft['draftId'] == entry.correlationId) {
        await journal.save(entry.advance(JournalStatus.committed));
        return JournalRecoveryOutcome.committed;
      }
      await journal.save(
        entry.advance(
          JournalStatus.failed,
          error: 'El borrador no fue persistido; no se inventaron datos.',
        ),
      );
      return JournalRecoveryOutcome.safelyCompensated;
    } on Object catch (error) {
      return _markManual(entry, 'Borrador inactivo ilegible: $error');
    }
  }

  Future<JournalRecoveryOutcome> _recoverInactiveClosureDraftDiscard(
    OperationJournalEntry entry,
  ) async {
    const slot = 'no_hydrant_at_location';
    const terminalQueueStatus = 'discardedLocalInactiveDraft';
    final inspectionId = entry.entityIds.firstOrNull;
    final photoIds = entry.entityIds.skip(1).toSet();
    if (inspectionId == null) {
      return _markManual(entry, 'Descarte inactivo sin identidad completa.');
    }
    final inspections = Hive.box<String>('visual_inspections_v1');
    final photos = Hive.box<String>('inspection_photos_v1');
    final mediaWork = Hive.box<String>('media_work_queue_v1');
    final mediaSync = Hive.box<String>('media_sync_queue');
    final inspectionRaw = inspections.get(inspectionId);
    if (inspectionRaw == null) {
      return _markManual(
        entry,
        'No existe la revisión del descarte; la evidencia se conservó.',
      );
    }
    try {
      final document = VersionedJsonCodec.decode(inspectionRaw);
      final payload = Map<String, dynamic>.from(document.payload);
      final rawDraft = payload['rvDynamicDraft'];
      if (rawDraft is! Map) {
        return _markManual(entry, 'La revisión no contiene un borrador RV.');
      }
      final draft = Map<String, dynamic>.from(rawDraft);
      if (draft['inactiveClosure'] is Map ||
          draft['localStatus'] == 'inactive') {
        return _markManual(
          entry,
          'El cierre ya fue confirmado; no se descartó evidencia.',
        );
      }
      final photosBySlot = Map<String, dynamic>.from(
        draft['photos'] as Map? ?? const {},
      );
      final dedicated = (photosBySlot[slot] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false);
      final referencedIds = dedicated
          .map((value) => '${value['photoId'] ?? ''}')
          .where((value) => value.isNotEmpty)
          .toSet();
      if (referencedIds.isEmpty && draft['inactiveClosureDraft'] == null) {
        var alreadyComplete = true;
        for (final photoId in photoIds) {
          final raw = photos.get(photoId);
          if (raw == null) {
            alreadyComplete = false;
            break;
          }
          final photo = InspectionPhoto.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          if (!photo.isDeleted ||
              photo.inspectionId.toLowerCase() != inspectionId.toLowerCase() ||
              photo.category != slot ||
              MediaWorkItemCodec.statusOf(photoId, mediaWork.get(photoId)) !=
                  terminalQueueStatus ||
              MediaWorkItemCodec.statusOf(photoId, mediaSync.get(photoId)) !=
                  terminalQueueStatus) {
            alreadyComplete = false;
            break;
          }
        }
        if (alreadyComplete) {
          await journal.save(entry.advance(JournalStatus.committed));
          return JournalRecoveryOutcome.committed;
        }
      }
      if (!photoIds.containsAll(referencedIds) ||
          !referencedIds.containsAll(photoIds)) {
        return _markManual(
          entry,
          'La evidencia dedicada no coincide con el journal; no se modificó.',
        );
      }
      for (final raw in inspections.toMap().entries) {
        final otherDocument = VersionedJsonCodec.decode(raw.value);
        final otherRawDraft = otherDocument.payload['rvDynamicDraft'];
        if (otherRawDraft is! Map) continue;
        final otherDraft = Map<String, dynamic>.from(otherRawDraft);
        final otherPhotos = Map<String, dynamic>.from(
          otherDraft['photos'] as Map? ?? const {},
        );
        final referencedSlots = <String>[
          for (final slotEntry in otherPhotos.entries)
            if ((slotEntry.value as List? ?? const []).whereType<Map>().any(
              (item) => photoIds.contains('${item['photoId'] ?? ''}'),
            ))
              slotEntry.key,
        ];
        final closure = otherDraft['inactiveClosure'];
        final confirmedElsewhere =
            closure is Map &&
            (closure['photoIds'] as List? ?? const []).any(
              (id) => photoIds.contains('$id'),
            );
        if ((referencedSlots.isNotEmpty && '${raw.key}' != inspectionId) ||
            referencedSlots.any((referencedSlot) => referencedSlot != slot) ||
            confirmedElsewhere) {
          return _markManual(
            entry,
            'La evidencia está referenciada por otro documento o cierre.',
          );
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (final photoId in photoIds) {
        final photoRaw = photos.get(photoId);
        if (photoRaw == null) {
          return _markManual(
            entry,
            'Falta un documento de foto; no se completó el descarte.',
          );
        }
        final photo = Map<String, dynamic>.from(jsonDecode(photoRaw) as Map);
        final localOnly =
            photo['inspectionId']?.toString().toLowerCase() ==
                inspectionId.toLowerCase() &&
            photo['category'] == slot &&
            photo['capturedByUserId']?.toString().toLowerCase() ==
                entry.actor.toLowerCase() &&
            photo['deviceId']?.toString().toLowerCase() ==
                entry.deviceId.toLowerCase() &&
            photo['uploadedAt'] == null &&
            photo['verifiedAt'] == null &&
            photo['remoteObjectKey'] == null &&
            photo['remoteSha256'] == null &&
            photo['syncStatus'] == 'pendingUpload';
        if (!localOnly) {
          return _markManual(
            entry,
            'Una foto no es evidencia local exclusiva; se conservó intacta.',
          );
        }
      }
      for (final photoId in photoIds) {
        final photo = Map<String, dynamic>.from(
          jsonDecode(photos.get(photoId)!) as Map,
        );
        photo
          ..['deletedAt'] ??= now
          ..['updatedAt'] = now
          ..['discardReason'] = 'inactiveClosureDraftDiscarded'
          ..['discardOperationId'] = entry.operationId;
        await photos.put(photoId, jsonEncode(photo));
        final resolved = MediaWorkItemCodec.pending(
          photoId: photoId,
          inspectionId: inspectionId,
          slotCode: slot,
          status: terminalQueueStatus,
        );
        await mediaWork.put(photoId, resolved);
        await mediaSync.put(photoId, resolved);
      }
      photosBySlot.remove(slot);
      draft
        ..['photos'] = photosBySlot
        ..['inactiveClosureDraft'] = null
        ..['photosStatus'] = 'pending'
        ..['updatedAt'] = now;
      payload['rvDynamicDraft'] = draft;
      await inspections.put(
        inspectionId,
        VersionedJsonCodec.encode(
          schemaVersion: document.schemaVersion,
          payload: payload,
        ),
      );
      final confirmed = VersionedJsonCodec.decode(
        inspections.get(inspectionId)!,
      ).payload['rvDynamicDraft'];
      if (confirmed is! Map ||
          confirmed['inactiveClosureDraft'] != null ||
          Map<String, dynamic>.from(
            confirmed['photos'] as Map? ?? const {},
          ).containsKey(slot)) {
        return _markManual(entry, 'El descarte no pudo verificarse.');
      }
      for (final photoId in photoIds) {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(photos.get(photoId)!) as Map),
        );
        if (!photo.isDeleted ||
            MediaWorkItemCodec.statusOf(photoId, mediaWork.get(photoId)) !=
                terminalQueueStatus ||
            MediaWorkItemCodec.statusOf(photoId, mediaSync.get(photoId)) !=
                terminalQueueStatus) {
          return _markManual(entry, 'El descarte no pudo verificarse.');
        }
      }
      await journal.save(entry.advance(JournalStatus.committed));
      return JournalRecoveryOutcome.committed;
    } on Object catch (error) {
      return _markManual(entry, 'Descarte conservado para revisión: $error');
    }
  }

  Future<JournalRecoveryOutcome> _recoverPhotoOperation(
    OperationJournalEntry entry,
  ) async {
    final photos = Hive.box<String>('inspection_photos_v1');
    final queue = Hive.box<String>('media_work_queue_v1');
    final photoId = _isPendingExternalCamera(entry)
        ? entry.operationId
        : entry.entityIds.firstOrNull;
    if (photoId == null) {
      return _markManual(entry, 'capturePhoto sin photoId.');
    }
    final raw = photos.get(photoId);
    if (raw == null) {
      return _markManual(
        entry,
        'No existe documento de foto; los archivos declarados se conservan.',
      );
    }
    try {
      final photo = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final localPath = photo['localPath'] as String?;
      if (localPath == null || !File(localPath).existsSync()) {
        return _markManual(entry, 'Documento de foto sin original válido.');
      }
      if (!queue.containsKey(photoId)) {
        await queue.put(
          photoId,
          jsonEncode({
            'photoId': photoId,
            'status': 'pendingUpload',
            'recoveredAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
      final inspectionId = photo['inspectionId']?.toString();
      final inspectionRaw = inspectionId == null
          ? null
          : Hive.box<String>('visual_inspections_v1').get(inspectionId);
      if (inspectionRaw == null ||
          !_draftReferencesPhoto(inspectionRaw, photoId)) {
        return _markManual(
          entry,
          'Foto conservada; falta enlazarla al draft antes de confirmar.',
        );
      }
      await journal.save(entry.advance(JournalStatus.committed));
      return JournalRecoveryOutcome.committed;
    } on Object catch (error) {
      return _markManual(entry, 'Documento de foto ilegible: $error');
    }
  }

  bool _isPendingExternalCamera(OperationJournalEntry entry) =>
      entry.operationType == JournalOperationType.capturePhoto &&
      const {
        'camera-pending-v1',
        'camera-pending-v2',
        'picker-pending-v1',
      }.contains(entry.entityIds.firstOrNull);

  bool _draftReferencesPhoto(String rawInspection, String photoId) {
    try {
      final payload = VersionedJsonCodec.decode(rawInspection).payload;
      final draft = payload['rvDynamicDraft'];
      if (draft is! Map) return false;
      final photos = draft['photos'];
      if (photos is! Map) return false;
      return photos.values
          .whereType<List>()
          .expand((items) => items)
          .any((item) => item is Map && '${item['photoId']}' == photoId);
    } on Object {
      return false;
    }
  }

  bool _documentsExist(OperationJournalEntry entry) {
    if (entry.documentWrites.isEmpty) return true;
    final boxes = _documentBoxes(entry.operationType);
    return entry.documentWrites.every(
      (id) => boxes.any((box) => box.containsKey(id)),
    );
  }

  bool _anyDocumentExists(OperationJournalEntry entry) {
    if (entry.documentWrites.isEmpty) return false;
    final boxes = _documentBoxes(entry.operationType);
    return entry.documentWrites.any(
      (id) => boxes.any((box) => box.containsKey(id)),
    );
  }

  bool _queuesExist(OperationJournalEntry entry) {
    if (entry.queueWrites.isEmpty) return true;
    final boxes = [
      Hive.box<String>('media_work_queue_v1'),
      Hive.box<String>('sync_queue'),
    ];
    return entry.queueWrites.every(
      (id) => boxes.any((box) => box.containsKey(id)),
    );
  }

  bool _anyQueueExists(OperationJournalEntry entry) {
    if (entry.queueWrites.isEmpty) return false;
    final boxes = [
      Hive.box<String>('media_work_queue_v1'),
      Hive.box<String>('sync_queue'),
    ];
    return entry.queueWrites.any(
      (id) => boxes.any((box) => box.containsKey(id)),
    );
  }

  List<Box<String>> _documentBoxes(JournalOperationType type) => switch (type) {
    JournalOperationType.createVisualReport ||
    JournalOperationType.finalizeVisualReport ||
    JournalOperationType.saveInactiveClosureDraft ||
    JournalOperationType.closeInactiveVisualReport => [
      Hive.box<String>('visual_inspections_v1'),
    ],
    JournalOperationType.createFunctionalReport ||
    JournalOperationType.finalizeFunctionalReport => [
      Hive.box<String>('functional_inspections_v1'),
    ],
    JournalOperationType.createVisualAndFunctional => [
      Hive.box<String>('visual_inspections_v1'),
      Hive.box<String>('functional_inspections_v1'),
    ],
    JournalOperationType.capturePhoto || JournalOperationType.deletePhoto => [
      Hive.box<String>('inspection_photos_v1'),
    ],
    JournalOperationType.createHydrant ||
    JournalOperationType.createTemporaryHydrant => [
      Hive.box<String>('local_hydrants_v1'),
    ],
    JournalOperationType.createRevision => [
      Hive.box<String>('visual_inspections_v1'),
      Hive.box<String>('functional_inspections_v1'),
      Hive.box<String>('report_revisions_v1'),
    ],
    JournalOperationType.discardInactiveClosureDraft ||
    JournalOperationType.repairIndex ||
    JournalOperationType.enqueueSync => [],
  };

  Future<bool> _repairReportIndex(OperationJournalEntry entry) async {
    final isVisual =
        entry.operationType == JournalOperationType.createVisualReport ||
        entry.operationType == JournalOperationType.finalizeVisualReport ||
        entry.operationType == JournalOperationType.saveInactiveClosureDraft ||
        entry.operationType == JournalOperationType.closeInactiveVisualReport;
    final isFunctional =
        entry.operationType == JournalOperationType.createFunctionalReport ||
        entry.operationType == JournalOperationType.finalizeFunctionalReport;
    if (!isVisual && !isFunctional) return false;
    final documents = Hive.box<String>(
      isVisual ? 'visual_inspections_v1' : 'functional_inspections_v1',
    );
    final index = Hive.box<String>(
      isVisual
          ? 'active_inspection_index_v1'
          : 'active_functional_inspection_index_v1',
    );
    final id = entry.documentWrites.firstOrNull;
    final raw = id == null ? null : documents.get(id);
    if (raw == null) return false;
    try {
      final payload = VersionedJsonCodec.decode(raw).payload;
      final hydrantId = payload['hydrantId'] as String?;
      final status = payload['status'] as String?;
      if (hydrantId == null) return false;
      final terminal = const {
        'completed',
        'cancelled',
        'synced',
      }.contains(status);
      final reportType = isVisual ? 'f02A' : 'f02B';
      final key = _activeIndexKey(payload, hydrantId, reportType);
      if (terminal) {
        final legacyKey = '$hydrantId:$reportType';
        for (final candidate in {legacyKey, key}) {
          if (index.get(candidate) == id) await index.delete(candidate);
        }
      } else {
        await index.put(key, id!);
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<JournalRecoveryOutcome> _markManual(
    OperationJournalEntry entry,
    String message,
  ) async {
    if (entry.status != JournalStatus.needsRecovery) {
      await journal.save(
        entry.advance(JournalStatus.needsRecovery, error: message),
      );
    }
    return JournalRecoveryOutcome.manualReview;
  }
}

enum JournalRecoveryOutcome {
  committed,
  safelyCompensated,
  manualReview,
  quarantined,
}
