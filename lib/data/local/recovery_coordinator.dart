import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/integrity/integrity_models.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../domain/media/inspection_photo.dart';
import 'integrity_audit_service.dart';
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
                '$hydrantId:${issue.entityType == 'visualInspection' ? 'f02A' : 'f02B'}',
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

  Future<JournalRecoveryOutcome> recoverJournalEntry(
    OperationJournalEntry entry,
  ) async {
    if (entry.status == JournalStatus.committed) {
      return JournalRecoveryOutcome.committed;
    }
    if (entry.status == JournalStatus.quarantined) {
      return JournalRecoveryOutcome.quarantined;
    }
    if (entry.status == JournalStatus.prepared) {
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

  Future<JournalRecoveryOutcome> _recoverPhotoOperation(
    OperationJournalEntry entry,
  ) async {
    final photos = Hive.box<String>('inspection_photos_v1');
    final queue = Hive.box<String>('media_work_queue_v1');
    final photoId = entry.entityIds.firstOrNull;
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
      await journal.save(entry.advance(JournalStatus.committed));
      return JournalRecoveryOutcome.committed;
    } on Object catch (error) {
      return _markManual(entry, 'Documento de foto ilegible: $error');
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
    JournalOperationType.finalizeVisualReport => [
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
    JournalOperationType.repairIndex || JournalOperationType.enqueueSync => [],
  };

  Future<bool> _repairReportIndex(OperationJournalEntry entry) async {
    final isVisual =
        entry.operationType == JournalOperationType.createVisualReport ||
        entry.operationType == JournalOperationType.finalizeVisualReport;
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
      final key = '$hydrantId:${isVisual ? 'f02A' : 'f02B'}';
      if (terminal) {
        if (index.get(key) == id) await index.delete(key);
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
