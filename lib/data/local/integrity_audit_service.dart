import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../core/security/f02a_scoped_identity.dart';
import '../../domain/integrity/integrity_models.dart';
import '../../domain/integrity/operation_journal.dart';
import '../../domain/media/inspection_photo.dart';
import '../../domain/functional/functional_models.dart';
import 'report_revision_resolver_service.dart';

class IntegrityAuditService {
  const IntegrityAuditService();

  /// Stores a new audit only when its observable issue set changed from the
  /// latest persisted audit. Audit IDs and timing metadata are diagnostic,
  /// not a reason to mutate local state during an otherwise idle bootstrap.
  Future<bool> persistIfChanged(
    Box<String> box,
    IntegrityAuditReport report, {
    String? stateFingerprint,
  }) async {
    final fingerprint = stateFingerprint ?? auditStateFingerprint();
    String? latest;
    _AuditOrder? latestOrder;
    for (final entry in box.toMap().entries) {
      try {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(entry.value) as Map,
        );
        final order = _AuditOrder.fromJson(decoded, storageKey: '${entry.key}');
        if (latestOrder == null || order.compareTo(latestOrder) > 0) {
          latest = entry.value;
          latestOrder = order;
        }
      } on Object {
        // An unreadable audit is retained but cannot represent the latest
        // comparable semantic result.
      }
    }
    if (latest != null && _semanticallyMatches(latest, report, fingerprint)) {
      return false;
    }
    await box.put(
      report.id,
      jsonEncode({...report.toJson(), 'stateFingerprint': fingerprint}),
    );
    return true;
  }

  /// Deterministic identity of all persisted inputs inspected by this audit.
  /// It includes photo path/hash/size metadata and physical presence/length,
  /// but deliberately excludes the audit-report box itself.
  String auditStateFingerprint() {
    final boxes = <String, Object?>{};
    for (final name in const [
      'active_inspection_index_v1',
      'visual_inspections_v1',
      'active_functional_inspection_index_v1',
      'functional_inspections_v1',
      'measurement_series_v1',
      'instrument_records_v1',
      'functional_results_v1',
      'inspection_photos_v1',
      'operation_journal_v1',
      'media_work_queue_v1',
      'report_revisions_v1',
    ]) {
      boxes[name] = _canonicalBox(Hive.box<String>(name));
    }
    final physical = <String, Object?>{};
    for (final entry in Hive.box<String>(
      'inspection_photos_v1',
    ).toMap().entries) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        final file = File(photo.localPath);
        final exists = file.existsSync();
        physical['${entry.key}'] = {
          'path': photo.localPath,
          'declaredSize': photo.fileSize,
          'declaredHash': photo.sha256,
          'exists': exists,
          if (exists) 'length': file.lengthSync(),
          if (exists)
            'modifiedMicros': file
                .lastModifiedSync()
                .toUtc()
                .microsecondsSinceEpoch,
        };
      } on Object {
        physical['${entry.key}'] = const {'metadataReadable': false};
      }
    }
    boxes['physicalPhotos'] = physical;
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(boxes))))
        .toString();
  }

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

  bool _semanticallyMatches(
    String raw,
    IntegrityAuditReport report,
    String stateFingerprint,
  ) {
    try {
      final stored = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final storedIssues =
          (stored['issues'] as List? ?? const [])
              .whereType<Map>()
              .map((value) => _issueIdentity(Map<String, dynamic>.from(value)))
              .toList()
            ..sort();
      final currentIssues =
          report.issues.map((issue) => _issueIdentity(issue.toJson())).toList()
            ..sort();
      return stored['schemaVersion'] == report.schemaVersion &&
          stored['stateFingerprint'] == stateFingerprint &&
          _sameStrings(storedIssues, currentIssues);
    } on Object {
      return false;
    }
  }

  Map<String, Object?> _canonicalBox(Box<String> box) => {
    for (final entry in box.toMap().entries)
      '${entry.key}': _canonicalRaw(entry.value),
  };

  Object? _canonicalRaw(String raw) {
    try {
      return _canonicalize(jsonDecode(raw));
    } on FormatException {
      return raw;
    }
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  String _issueIdentity(Map<String, dynamic> value) {
    final stable = Map<String, dynamic>.from(value)..remove('id');
    return jsonEncode(stable);
  }

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _auditIndex(
    List<IntegrityIssue> issues,
    Box<String> index,
    Box<String> documents,
    String entityType,
  ) {
    final indexEntries = index.toMap().entries.toList(growable: false);
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
            '$key'.contains('/')
                ? RecoveryAction.manualReview
                : RecoveryAction.removeOrphanIndex,
            automatic: !'$key'.contains('/'),
          ),
        );
      }
    }
    final candidates = <String, List<String>>{};
    final expectedKeysByDocument = <String, Set<String>>{};
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
          final documentId = '${entry.key}';
          candidates.putIfAbsent(hydrantId, () => []).add(documentId);
          expectedKeysByDocument[documentId] = _validActiveIndexKeys(
            payload,
            hydrantId,
            entityType == 'visualInspection' ? 'f02A' : 'f02B',
          );
        }
      } on Object {
        // Corrupt documents are reported separately.
      }
    }
    for (final candidate in candidates.entries) {
      for (final documentId in candidate.value) {
        final expectedKeys = expectedKeysByDocument[documentId]!;
        final scopedKeys = expectedKeys.where((key) => key.contains('/'));
        final requiredKeys = scopedKeys.isEmpty
            ? expectedKeys
            : scopedKeys.toSet();
        final indexed = indexEntries.any(
          (entry) =>
              entry.value == documentId &&
              requiredKeys.contains('${entry.key}'),
        );
        if (indexed) continue;
        final canRepairUnambiguously =
            scopedKeys.isNotEmpty || candidate.value.length == 1;
        issues.add(
          _issue(
            IntegrityIssueType.activeDocumentWithoutIndex,
            canRepairUnambiguously
                ? IntegritySeverity.high
                : IntegritySeverity.critical,
            entityType,
            documentId,
            canRepairUnambiguously
                ? 'Borrador incompleto recuperado.'
                : 'Datos locales requieren revisión.',
            canRepairUnambiguously
                ? 'Documento activo sin índice scoped para ${candidate.key}.'
                : 'Hay varios documentos legacy activos sin índice para ${candidate.key}.',
            canRepairUnambiguously
                ? RecoveryAction.recreateIndex
                : RecoveryAction.manualReview,
            automatic: canRepairUnambiguously,
          ),
        );
      }
    }
  }

  Set<String> _validActiveIndexKeys(
    Map<String, dynamic> payload,
    String hydrantId,
    String reportType,
  ) {
    final values = <String>{'$hydrantId:$reportType'};
    // F02B is shared with Levantamientos and its persisted index contract is
    // intentionally still legacy. Scoped keys are exclusive to DDR001 RV.
    if (reportType != 'f02A') return values;
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
      if (scopedKey != null) values.add(scopedKey);
    }
    return values;
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

class _AuditOrder implements Comparable<_AuditOrder> {
  const _AuditOrder({
    required this.timestamp,
    required this.id,
    required this.storageKey,
  });

  factory _AuditOrder.fromJson(
    Map<String, dynamic> value, {
    required String storageKey,
  }) {
    DateTime? timestamp(String field) =>
        DateTime.tryParse('${value[field] ?? ''}')?.toUtc();
    return _AuditOrder(
      timestamp: timestamp('completedAt') ?? timestamp('startedAt'),
      id: '${value['id'] ?? ''}',
      storageKey: storageKey,
    );
  }

  final DateTime? timestamp;
  final String id;
  final String storageKey;

  @override
  int compareTo(_AuditOrder other) {
    final left = timestamp;
    final right = other.timestamp;
    if (left != null && right == null) return 1;
    if (left == null && right != null) return -1;
    if (left != null && right != null) {
      final byTimestamp = left.compareTo(right);
      if (byTimestamp != 0) return byTimestamp;
    }
    final byId = id.compareTo(other.id);
    return byId != 0 ? byId : storageKey.compareTo(other.storageKey);
  }
}
