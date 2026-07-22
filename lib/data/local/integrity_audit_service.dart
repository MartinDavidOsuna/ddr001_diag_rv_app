import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/integrity/integrity_models.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../domain/media/inspection_photo.dart';
import '../../domain/functional/functional_models.dart';
import 'report_revision_resolver_service.dart';

class IntegrityAuditService {
  const IntegrityAuditService();

  IntegrityAuditReport runLightweight() {
    final started = DateTime.now().toUtc();
    final issues = <IntegrityIssue>[];
    _auditIndex(
      issues,
      Hive.box<String>('active_inspection_index_v1'),
      Hive.box<String>('visual_inspections_v1'),
      'visualInspection',
    );
    _auditIndex(
      issues,
      Hive.box<String>('active_functional_inspection_index_v1'),
      Hive.box<String>('functional_inspections_v1'),
      'functionalInspection',
    );
    _auditJsonBoxes(issues);
    _auditSeries(issues);
    _auditResults(issues);
    _auditPhotos(issues);
    _auditJournals(issues);
    _auditRevisions(issues);
    return IntegrityAuditReport(
      id: const Uuid().v4(),
      startedAt: started,
      completedAt: DateTime.now().toUtc(),
      issues: issues,
    );
  }

  void _auditIndex(
    List<IntegrityIssue> issues,
    Box<String> index,
    Box<String> documents,
    String entityType,
  ) {
    for (final key in index.keys) {
      final id = index.get(key);
      if (id != null && !documents.containsKey(id)) {
        issues.add(
          _issue(
            IntegrityIssueType.activeIndexWithoutDocument,
            IntegritySeverity.high,
            entityType,
            id,
            'Datos locales requieren revisión.',
            'Índice $key apunta a un documento inexistente.',
            RecoveryAction.removeOrphanIndex,
            automatic: true,
          ),
        );
      }
    }
    final candidates = <String, List<String>>{};
    for (final entry in documents.toMap().entries) {
      try {
        final payload = VersionedJsonCodec.decode(entry.value).payload;
        final hydrantId = payload['hydrantId'] as String?;
        final status = payload['status'] as String? ?? '';
        final active = !const {
          'completed',
          'cancelled',
          'synced',
          'validated',
        }.contains(status);
        if (hydrantId != null && active) {
          candidates.putIfAbsent(hydrantId, () => []).add('${entry.key}');
        }
      } on Object {
        // Corrupt documents are reported separately.
      }
    }
    for (final candidate in candidates.entries) {
      final key =
          '${candidate.key}:${entityType == 'visualInspection' ? 'f02A' : 'f02B'}';
      if (index.get(key) == null && candidate.value.length == 1) {
        issues.add(
          _issue(
            IntegrityIssueType.activeDocumentWithoutIndex,
            IntegritySeverity.high,
            entityType,
            candidate.value.single,
            'Borrador incompleto recuperado.',
            'Documento activo sin índice para ${candidate.key}.',
            RecoveryAction.recreateIndex,
            automatic: true,
          ),
        );
      } else if (index.get(key) == null && candidate.value.length > 1) {
        for (final id in candidate.value) {
          issues.add(
            _issue(
              IntegrityIssueType.activeDocumentWithoutIndex,
              IntegritySeverity.critical,
              entityType,
              id,
              'Datos locales requieren revisión.',
              'Hay varios documentos activos sin índice para ${candidate.key}.',
              RecoveryAction.manualReview,
            ),
          );
        }
      }
    }
  }

  void _auditJsonBoxes(List<IntegrityIssue> issues) {
    for (final name in const [
      'visual_inspections_v1',
      'functional_inspections_v1',
      'measurement_series_v1',
      'instrument_records_v1',
      'inspection_photos_v1',
      'operation_journal_v1',
    ]) {
      final box = Hive.box<String>(name);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null) continue;
        try {
          if (name == 'operation_journal_v1' ||
              name == 'inspection_photos_v1') {
            jsonDecode(raw);
          } else {
            VersionedJsonCodec.decode(raw);
          }
        } on Object catch (error) {
          issues.add(
            _issue(
              IntegrityIssueType.corruptJson,
              IntegritySeverity.critical,
              name,
              '$key',
              'Datos locales requieren revisión.',
              '$error',
              RecoveryAction.quarantineDocument,
            ),
          );
        }
      }
    }
  }

  void _auditSeries(List<IntegrityIssue> issues) {
    final instruments = Hive.box<String>('instrument_records_v1');
    final reports = Hive.box<String>('functional_inspections_v1');
    for (final entry in Hive.box<String>(
      'measurement_series_v1',
    ).toMap().entries) {
      try {
        final series = MeasurementSeries.fromJson(
          VersionedJsonCodec.decode(entry.value).payload,
        );
        if (!reports.containsKey(series.inspectionId)) {
          issues.add(
            _issue(
              IntegrityIssueType.openSeriesWithoutReport,
              IntegritySeverity.high,
              'measurementSeries',
              series.id,
              'Borrador incompleto recuperado.',
              'La serie referencia un RF inexistente.',
              RecoveryAction.manualReview,
            ),
          );
        }
        if (!instruments.containsKey(series.instrumentId)) {
          issues.add(
            _issue(
              IntegrityIssueType.seriesWithoutInstrument,
              IntegritySeverity.high,
              'measurementSeries',
              series.id,
              'Datos locales requieren revisión.',
              'La serie no tiene instrumento recuperable.',
              RecoveryAction.manualReview,
            ),
          );
        }
        final instrumentRaw = instruments.get(series.instrumentId);
        if (series.isActive && instrumentRaw != null) {
          final instrument = InstrumentRecord.fromJson(
            VersionedJsonCodec.decode(instrumentRaw).payload,
          );
          if (instrument.deletedAt != null) {
            issues.add(
              _issue(
                IntegrityIssueType.retiredInstrumentInActiveSeries,
                IntegritySeverity.critical,
                'measurementSeries',
                series.id,
                'Datos locales requieren revisión.',
                'La serie activa usa un instrumento retirado.',
                RecoveryAction.manualReview,
              ),
            );
          }
        }
      } on Object {
        // Already reported by JSON audit.
      }
    }
  }

  void _auditResults(List<IntegrityIssue> issues) {
    final reports = Hive.box<String>('functional_inspections_v1');
    for (final key in Hive.box<String>('functional_results_v1').keys) {
      if (!reports.containsKey(key)) {
        issues.add(
          _issue(
            IntegrityIssueType.resultWithoutReport,
            IntegritySeverity.high,
            'functionalResult',
            '$key',
            'Datos locales requieren revisión.',
            'Resultado sin REPORTE FUNCIONAL relacionado.',
            RecoveryAction.manualReview,
          ),
        );
      }
    }
  }

  void _auditPhotos(List<IntegrityIssue> issues) {
    final queue = Hive.box<String>('media_work_queue_v1');
    for (final entry in Hive.box<String>(
      'inspection_photos_v1',
    ).toMap().entries) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (!photo.isDeleted && !File(photo.localPath).existsSync()) {
          issues.add(
            _issue(
              IntegrityIssueType.photoWithoutFile,
              IntegritySeverity.high,
              'photo',
              photo.id,
              'Fotografía faltante.',
              'No existe ${photo.localPath}.',
              RecoveryAction.markMissingLocal,
              automatic: true,
            ),
          );
        }
        if (!photo.isDeleted &&
            (photo.thumbnailPath.isEmpty ||
                !File(photo.thumbnailPath).existsSync())) {
          issues.add(
            _issue(
              IntegrityIssueType.missingThumbnail,
              IntegritySeverity.warning,
              'photo',
              photo.id,
              'Miniatura pendiente de recuperación.',
              'No existe ${photo.thumbnailPath}.',
              RecoveryAction.regenerateThumbnail,
              automatic: File(photo.localPath).existsSync(),
            ),
          );
        }
        if (!photo.isDeleted && !queue.containsKey(photo.id)) {
          issues.add(
            _issue(
              IntegrityIssueType.photoWithoutQueue,
              IntegritySeverity.warning,
              'photo',
              photo.id,
              'Operación pendiente de recuperación.',
              'La fotografía no tiene trabajo de medios.',
              RecoveryAction.enqueuePhoto,
              automatic: true,
            ),
          );
        }
      } on Object {
        // Already reported by JSON audit.
      }
    }
  }

  void _auditJournals(List<IntegrityIssue> issues) {
    for (final entry in Hive.box<String>(
      'operation_journal_v1',
    ).toMap().entries) {
      try {
        final journal = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (journal.status != JournalStatus.committed &&
            journal.status != JournalStatus.quarantined) {
          issues.add(
            _issue(
              IntegrityIssueType.incompleteJournal,
              IntegritySeverity.high,
              'operationJournal',
              journal.operationId,
              'Operación pendiente de recuperación.',
              'Journal en estado ${journal.status.name}.',
              RecoveryAction.completeJournalOperation,
            ),
          );
        }
      } on Object {
        // Already reported as corrupt JSON.
      }
    }
  }

  void _auditRevisions(List<IntegrityIssue> issues) {
    const service = ReportRevisionResolverService();
    for (final reportType in const ['f02A', 'f02B']) {
      final boxName = reportType == 'f02A'
          ? 'visual_inspections_v1'
          : 'functional_inspections_v1';
      final hydrants = <String>{};
      for (final raw in Hive.box<String>(boxName).values) {
        try {
          final payload = VersionedJsonCodec.decode(raw).payload;
          final hydrantId = payload['hydrantId'] as String?;
          if (hydrantId != null && hydrantId.isNotEmpty) {
            hydrants.add(hydrantId);
          }
        } on Object {
          // La auditoría JSON ya registra el documento ilegible.
        }
      }
      for (final hydrantId in hydrants) {
        issues.addAll(
          service
              .resolveForHydrant(hydrantId: hydrantId, reportType: reportType)
              .issues,
        );
      }
    }
  }

  IntegrityIssue _issue(
    IntegrityIssueType type,
    IntegritySeverity severity,
    String entityType,
    String entityId,
    String userMessage,
    String technicalMessage,
    RecoveryAction action, {
    bool automatic = false,
  }) => IntegrityIssue(
    id: const Uuid().v4(),
    type: type,
    severity: severity,
    entityType: entityType,
    entityId: entityId,
    userMessage: userMessage,
    technicalMessage: technicalMessage,
    recommendedAction: action,
    repairableAutomatically: automatic,
  );
}
