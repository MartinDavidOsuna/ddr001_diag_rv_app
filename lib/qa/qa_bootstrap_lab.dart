import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app/local_recovery_pipeline.dart';
import '../core/media/file_digest_service.dart';
import '../core/persistence/versioned_json_codec.dart';
import '../data/local/media_work_item_codec.dart';
import '../data/local/visual_inspection_repository.dart';
import '../domain/integrity/operation_journal.dart';
import '../domain/media/inspection_photo.dart';
import '../features/inspections/data/rv_draft_repository.dart';

const qaObservedBootstrapBoxes = <String>[
  'visual_inspections_v1',
  'active_inspection_index_v1',
  'inspection_photos_v1',
  'media_work_queue_v1',
  'media_sync_queue',
  'operation_journal_v1',
  'quarantine_documents_v1',
  'integrity_audit_reports_v1',
  'rv_recovery_v1',
  'rv_recovery_snapshots_v1',
  'sync_queue',
];

/// Persisted inputs whose identity determines whether local recovery has work.
/// Recovery reports, snapshots and audits are outputs and must never make this
/// fingerprint invalidate itself on the next otherwise identical run.
const qaFunctionalBootstrapBoxes = <String>[
  'visual_inspections_v1',
  'active_inspection_index_v1',
  'inspection_photos_v1',
  'media_work_queue_v1',
  'media_sync_queue',
  'operation_journal_v1',
  'quarantine_documents_v1',
  'sync_queue',
];

const qaRecoveryOutputBoxes = <String>[
  'integrity_audit_reports_v1',
  'rv_recovery_v1',
  'rv_recovery_snapshots_v1',
];

const qaBootstrapSupportBoxes = <String>[
  'active_functional_inspection_index_v1',
  'functional_inspections_v1',
  'measurement_series_v1',
  'instrument_records_v1',
  'functional_results_v1',
  'report_revisions_v1',
];

class QaBootstrapRunReport {
  const QaBootstrapRunReport({
    required this.label,
    required this.startedAt,
    required this.completedAt,
    required this.fingerprintBefore,
    required this.fingerprintAfter,
    required this.writesByBox,
    required this.keysByBox,
    required this.changes,
    required this.stageMicros,
    required this.recoveryRunId,
    required this.recoveredPhotoReferences,
    required this.mediaIssues,
    required this.snapshotCountBefore,
    required this.snapshotCountAfter,
  });

  final String label;
  final DateTime startedAt;
  final DateTime completedAt;
  final String fingerprintBefore;
  final String fingerprintAfter;
  final Map<String, int> writesByBox;
  final Map<String, List<String>> keysByBox;
  final List<QaBootstrapChange> changes;
  final Map<String, int> stageMicros;
  final String recoveryRunId;
  final int recoveredPhotoReferences;
  final int mediaIssues;
  final int snapshotCountBefore;
  final int snapshotCountAfter;

  int get totalWrites => writesByBox.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'label': label,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'fingerprintBefore': fingerprintBefore,
    'fingerprintAfter': fingerprintAfter,
    'writesByBox': writesByBox,
    'keysByBox': keysByBox,
    'changes': changes.map((change) => change.toJson()).toList(),
    'stageMicros': stageMicros,
    'recoveryRunId': recoveryRunId,
    'recoveredPhotoReferences': recoveredPhotoReferences,
    'mediaIssues': mediaIssues,
    'snapshotCountBefore': snapshotCountBefore,
    'snapshotCountAfter': snapshotCountAfter,
  };
}

class QaBootstrapChange {
  const QaBootstrapChange({
    required this.stage,
    required this.box,
    required this.key,
    required this.beforeHash,
    required this.afterHash,
    required this.type,
  });

  final String stage;
  final String box;
  final String key;
  final String? beforeHash;
  final String? afterHash;
  final String type;

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'callSite': 'LocalRecoveryPipeline/$stage',
    'box': box,
    'key': key,
    'beforeHash': beforeHash,
    'afterHash': afterHash,
    'type': type,
  };
}

class QaCaptureDiagnostic {
  const QaCaptureDiagnostic(this.value);
  final Map<String, Object?> value;
  Map<String, Object?> toJson() => value;
}

Future<Directory> _defaultQaExportsDirectory() async {
  final applicationSupport = await getApplicationSupportDirectory();
  return Directory(p.join(applicationSupport.path, 'qa-diagnostic-reports'));
}

/// QA-only observer around the exact local pipeline used by production.
class QaBootstrapLab {
  QaBootstrapLab({
    required this.visualRepository,
    required this.drafts,
    required this.runtimeBox,
    Future<Directory> Function()? exportsDirectory,
    this.observeWrites = true,
  }) : _exportsDirectory = exportsDirectory ?? _defaultQaExportsDirectory;

  final VisualInspectionRepository visualRepository;
  final RvDraftRepository drafts;
  final Box<String> runtimeBox;
  final Future<Directory> Function() _exportsDirectory;
  final bool observeWrites;
  static Future<void> _serializedTail = Future<void>.value();
  static const _maxRetainedExports = 4;

  Future<QaBootstrapRunReport> run(String label) {
    final previous = _serializedTail;
    final released = Completer<void>();
    _serializedTail = released.future;
    return () async {
      await previous;
      try {
        return await _runSerialized(label);
      } finally {
        released.complete();
      }
    }();
  }

  Future<QaBootstrapRunReport> _runSerialized(String label) async {
    final boxes = {
      for (final name in qaObservedBootstrapBoxes) name: Hive.box<String>(name),
    };
    final events = {for (final name in boxes.keys) name: <BoxEvent>[]};
    final shadow = {
      for (final entry in boxes.entries)
        entry.key: Map<Object, String>.from(entry.value.toMap()),
    };
    final changes = <QaBootstrapChange>[];
    final subscriptions = <StreamSubscription<BoxEvent>>[];
    var currentStage = 'pipeline-start';
    if (observeWrites) {
      for (final entry in boxes.entries) {
        subscriptions.add(
          entry.value.watch().listen((event) {
            events[entry.key]!.add(event);
            final previous = shadow[entry.key]![event.key];
            final current = event.deleted ? null : event.value as String?;
            changes.add(
              QaBootstrapChange(
                stage: currentStage,
                box: entry.key,
                key: _sanitizedKey(event.key),
                beforeHash: _valueHash(previous),
                afterHash: _valueHash(current),
                type: previous == null
                    ? 'insert'
                    : current == null
                    ? 'delete'
                    : 'update',
              ),
            );
            if (current == null) {
              shadow[entry.key]!.remove(event.key);
            } else {
              shadow[entry.key]![event.key] = current;
            }
          }),
        );
      }
    }
    final before = functionalFingerprint(
      boxes,
      scopeNamespace: visualRepository.accessScopeNamespace,
    );
    final snapshotCountBefore = boxes['rv_recovery_snapshots_v1']!.length;
    final started = DateTime.now().toUtc();
    final stageMicros = <String, int>{};
    try {
      final result = await LocalRecoveryPipeline(
        visualRepository: visualRepository,
        drafts: drafts,
        operationJournalBox: boxes['operation_journal_v1']!,
        quarantineBox: boxes['quarantine_documents_v1']!,
        recoveryBox: boxes['rv_recovery_v1']!,
        snapshotBox: boxes['rv_recovery_snapshots_v1']!,
        indexBox: boxes['active_inspection_index_v1']!,
        syncQueueBox: Hive.box<String>('sync_queue'),
        photoBox: boxes['inspection_photos_v1']!,
        mediaQueueBox: boxes['media_sync_queue']!,
        integrityReportBox: boxes['integrity_audit_reports_v1']!,
        onStageStarted: (name) => currentStage = name,
        onStage: (name, elapsed) {
          stageMicros[name] = elapsed.inMicroseconds;
        },
      ).run();
      await Future<void>.delayed(Duration.zero);
      final report = QaBootstrapRunReport(
        label: label,
        startedAt: started,
        completedAt: DateTime.now().toUtc(),
        fingerprintBefore: before,
        fingerprintAfter: functionalFingerprint(
          boxes,
          scopeNamespace: visualRepository.accessScopeNamespace,
        ),
        writesByBox: {
          for (final entry in events.entries) entry.key: entry.value.length,
        },
        keysByBox: {
          for (final entry in events.entries)
            entry.key:
                entry.value
                    .map((event) => _sanitizedKey(event.key))
                    .toSet()
                    .toList()
                  ..sort(),
        },
        changes: List.unmodifiable(changes),
        stageMicros: Map.unmodifiable(stageMicros),
        recoveryRunId: result.rvRecovery.runId,
        recoveredPhotoReferences: result.recoveredPhotoReferences,
        mediaIssues: result.mediaIssues,
        snapshotCountBefore: snapshotCountBefore,
        snapshotCountAfter: boxes['rv_recovery_snapshots_v1']!.length,
      );
      await runtimeBox.put(
        'bootstrapReport:$label',
        jsonEncode(report.toJson()),
      );
      return report;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  Future<void> createLegacyRecoveryWithoutFingerprint() async {
    final recovery = Hive.box<String>('rv_recovery_v1');
    final current = recovery.get('current');
    final payload = current == null
        ? <String, dynamic>{
            'recoverySchemaVersion': 1,
            'runId': 'qa-legacy-recovery-baseline',
            'phase': 'complete',
            'status': 'completed',
            'startedAt': DateTime.utc(2026, 8, 28).toIso8601String(),
            'completedAt': DateTime.utc(2026, 8, 28).toIso8601String(),
          }
        : Map<String, dynamic>.from(jsonDecode(current) as Map);
    payload
      ..['status'] = 'completed'
      ..remove('stateFingerprint');
    await recovery.put('current', jsonEncode(payload));
  }

  Future<File> exportComparison() async {
    final reportEntries =
        runtimeBox
            .toMap()
            .entries
            .where((entry) => '${entry.key}'.startsWith('bootstrapReport:'))
            .toList()
          ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    final reports = reportEntries
        .map((entry) => jsonDecode(entry.value))
        .toList(growable: false);
    final captures = await captureDiagnostics();
    final operationalState = _operationalState(captures);
    final root = await _exportsDirectory();
    await root.create(recursive: true);
    final file = File(
      p.join(
        root.path,
        'qa_bootstrap_comparison_${DateTime.now().toUtc().microsecondsSinceEpoch}.json',
      ),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'environment': 'qa',
        'productionDataIncluded': false,
        'reports': reports,
        'captures': captures.map((capture) => capture.toJson()).toList(),
        'operationalState': operationalState,
      }),
      flush: true,
    );
    await _removeExpiredExports(root, keep: file.path);
    return file;
  }

  Future<void> _removeExpiredExports(
    Directory root, {
    required String keep,
  }) async {
    final exports = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!RegExp(r'^qa_bootstrap_comparison_[0-9]+\.json$').hasMatch(name)) {
        continue;
      }
      exports.add(entity);
    }
    exports.sort((left, right) => right.path.compareTo(left.path));
    final retained = <String>{keep};
    for (final export in exports) {
      if (retained.length >= _maxRetainedExports) break;
      retained.add(export.path);
    }
    for (final export in exports) {
      if (retained.contains(export.path)) continue;
      try {
        await export.delete();
      } on FileSystemException {
        // Export cleanup is best-effort and never changes measured boxes.
      }
    }
  }

  Future<List<QaCaptureDiagnostic>> captureDiagnostics() async {
    final values = <QaCaptureDiagnostic>[];
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final journalBox = Hive.box<String>('operation_journal_v1');
    final workBox = Hive.box<String>('media_work_queue_v1');
    final syncBox = Hive.box<String>('media_sync_queue');
    final digest = const StreamingFileDigestService();
    final qaReviewPayloads = <String, Map<String, dynamic>>{};
    for (final rawInspection in visualRepository.documents.values) {
      try {
        final payload = VersionedJsonCodec.decode(rawInspection).payload;
        if (payload['qaFixture'] != true) continue;
        final reviewId = '${payload['id'] ?? ''}';
        if (!reviewId.startsWith('qa-review-')) continue;
        qaReviewPayloads[reviewId] = payload;
      } on Object {
        // Unreadable documents are not interpreted as QA fixtures.
      }
    }
    for (final reviewEntry in qaReviewPayloads.entries) {
      try {
        final reviewId = reviewEntry.key;
        final rawScope = reviewEntry.value['dataScope'];
        final scopeHash = rawScope is Map
            ? sha256
                  .convert(
                    utf8.encode(
                      jsonEncode(
                        _canonicalize(Map<String, dynamic>.from(rawScope)),
                      ),
                    ),
                  )
                  .toString()
                  .substring(0, 16)
            : null;
        final draft = reviewEntry.value[RvDraftRepository.storageKey];
        final references = <String>[];
        if (draft is Map) {
          final rawPhotos = draft['photos'];
          if (rawPhotos is Map) {
            for (final items in rawPhotos.values.whereType<List>()) {
              for (final item in items.whereType<Map>()) {
                final photoId = '${item['photoId'] ?? ''}';
                if (photoId.isNotEmpty) references.add(photoId);
              }
            }
          }
        }
        final candidateIds = references.toSet();
        for (final photoEntry in photoBox.toMap().entries) {
          try {
            final photo = InspectionPhoto.fromJson(
              Map<String, dynamic>.from(jsonDecode(photoEntry.value) as Map),
            );
            if (photo.inspectionId.toLowerCase() == reviewId.toLowerCase()) {
              candidateIds.add('${photoEntry.key}');
            }
          } on Object {
            // An unreadable document is not adopted by a synthetic report.
          }
        }
        for (final journalEntry in journalBox.toMap().entries) {
          try {
            final journal = OperationJournalEntry.fromJson(
              Map<String, dynamic>.from(jsonDecode(journalEntry.value) as Map),
            );
            if (journal.operationType == JournalOperationType.capturePhoto &&
                journal.actor == 'qa-user' &&
                journal.deviceId == 'qa-device' &&
                journal.entityIds.length > 1 &&
                journal.entityIds[1].toLowerCase() == reviewId.toLowerCase()) {
              candidateIds.add(journal.operationId);
            }
          } on Object {
            // Unreadable journals remain untouched and unaffiliated.
          }
        }
        for (final photoId in candidateIds) {
          final rawPhoto = photoBox.get(photoId);
          InspectionPhoto? photo;
          try {
            if (rawPhoto != null) {
              photo = InspectionPhoto.fromJson(
                Map<String, dynamic>.from(jsonDecode(rawPhoto) as Map),
              );
            }
          } on Object {
            photo = null;
          }
          final original = photo == null ? null : File(photo.localPath);
          final exists = original != null && await original.exists();
          final journalRaw = journalBox.get(photoId);
          OperationJournalEntry? journal;
          try {
            if (journalRaw != null) {
              journal = OperationJournalEntry.fromJson(
                Map<String, dynamic>.from(jsonDecode(journalRaw) as Map),
              );
            }
          } on Object {
            journal = null;
          }
          final matchingReferences = references
              .where((value) => value.toLowerCase() == photoId.toLowerCase())
              .length;
          final referenceIndex = references.indexWhere(
            (value) => value.toLowerCase() == photoId.toLowerCase(),
          );
          final modifiedAt = exists ? await original.lastModified() : null;
          values.add(
            QaCaptureDiagnostic({
              'captureId': photoId,
              'journalMarker': journal?.entityIds.firstOrNull,
              'journalVersion': journal?.schemaVersion,
              'journalStatus': journal?.status.name ?? 'missing',
              'photoId': photoId,
              'reviewId': reviewId,
              'slot': photo?.category,
              'scopeHash': scopeHash,
              'sourcePresent':
                  journal?.fileWrites.any(
                    (path) =>
                        path.endsWith('.source.jpg') && File(path).existsSync(),
                  ) ??
                  false,
              'finalPresent': exists,
              'fileSize': exists ? await original.length() : null,
              'fileModifiedAt': modifiedAt?.toUtc().toIso8601String(),
              'fileModifiedMicros': modifiedAt?.toUtc().microsecondsSinceEpoch,
              'capturedAt': photo?.capturedAt.toUtc().toIso8601String(),
              'receivedSha256': photo?.receivedSha256,
              'normalizedSha256': photo?.sha256,
              'physicalSha256': exists ? await digest.sha256Of(original) : null,
              'photoSyncStatus': photo?.syncStatus.name,
              'photoIntegrityStatus': photo?.integrityStatus.name,
              'documentPresent': rawPhoto != null,
              'workQueuePresent': workBox.containsKey(photoId),
              'workQueueStatus': MediaWorkItemCodec.statusOf(
                photoId,
                workBox.get(photoId),
              ),
              'syncQueuePresent': syncBox.containsKey(photoId),
              'syncQueueStatus': MediaWorkItemCodec.statusOf(
                photoId,
                syncBox.get(photoId),
              ),
              'associatedToDraft': matchingReferences > 0,
              'referenceOrdinal': referenceIndex < 0
                  ? null
                  : referenceIndex + 1,
              'duplicateReferences': matchingReferences > 1,
              'stagingCleanAfterCommit':
                  journal?.status == JournalStatus.committed
                  ? !(journal?.fileWrites.any(
                          (path) =>
                              path.endsWith('.source.jpg') &&
                              File(path).existsSync(),
                        ) ??
                        false)
                  : null,
            }),
          );
        }
      } on Object {
        // Synthetic diagnostics are conservative: unreadable documents are
        // omitted rather than interpreted or mutated.
      }
    }
    values.sort(
      (left, right) =>
          '${left.value['photoId']}'.compareTo('${right.value['photoId']}'),
    );
    return values;
  }

  Map<String, Object?> _operationalState(List<QaCaptureDiagnostic> captures) {
    final activeIndex = Hive.box<String>('active_inspection_index_v1');
    final activeEntries =
        activeIndex
            .toMap()
            .entries
            .where(
              (entry) =>
                  '${entry.key}'.toLowerCase().contains('qa-') ||
                  entry.value.toLowerCase().startsWith('qa-review-'),
            )
            .map(
              (entry) => <String, String>{
                'key': '${entry.key}',
                'reviewId': entry.value,
              },
            )
            .toList()
          ..sort((left, right) => left['key']!.compareTo(right['key']!));

    final captureIds = captures
        .map((capture) => '${capture.value['captureId'] ?? ''}'.toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final journalStatuses = <String, int>{};
    final pendingJournalIds = <String>[];
    for (final entry in Hive.box<String>(
      'operation_journal_v1',
    ).toMap().entries) {
      try {
        final journal = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (!captureIds.contains(journal.operationId.toLowerCase())) continue;
        journalStatuses.update(
          journal.status.name,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (journal.status != JournalStatus.committed) {
          pendingJournalIds.add(journal.operationId);
        }
      } on Object {
        pendingJournalIds.add('${entry.key}');
        journalStatuses.update(
          'unreadable',
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    pendingJournalIds.sort();

    final workQueueStatuses = <String, int>{};
    var workQueueRecords = 0;
    var syncQueueRecords = 0;
    for (final capture in captures) {
      if (capture.value['workQueuePresent'] == true) {
        workQueueRecords++;
        final status = '${capture.value['workQueueStatus'] ?? 'unreadable'}';
        workQueueStatuses.update(
          status,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (capture.value['syncQueuePresent'] == true) syncQueueRecords++;
    }

    final recoveryStatuses = <String, int>{};
    for (final raw in Hive.box<String>('rv_recovery_v1').values) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final status = '${payload['status'] ?? payload['phase'] ?? 'unknown'}';
        recoveryStatuses.update(
          status,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      } on Object {
        recoveryStatuses.update(
          'unreadable',
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return {
      'activeIndexEntries': activeEntries,
      'scopedIndexKeys': activeEntries
          .map((entry) => entry['key']!)
          .where((key) => key.contains('/'))
          .toList(),
      'legacyIndexKeys': activeEntries
          .map((entry) => entry['key']!)
          .where((key) => !key.contains('/'))
          .toList(),
      'journalStatusCounts': Map.fromEntries(
        journalStatuses.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'pendingJournalCount': pendingJournalIds.length,
      'pendingJournalIds': pendingJournalIds,
      'workQueueRecordCount': workQueueRecords,
      'workQueueStatusCounts': Map.fromEntries(
        workQueueStatuses.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'syncQueueRecordCount': syncQueueRecords,
      'networkEligibleJobCount': 0,
      'networkPolicy': 'qa_sync_blocked',
      'recoveryStatusCounts': Map.fromEntries(
        recoveryStatuses.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'recoveryRunningCount': recoveryStatuses['running'] ?? 0,
      'recoveryFailedCount': recoveryStatuses['failed'] ?? 0,
      'snapshotCount': Hive.box<String>('rv_recovery_snapshots_v1').length,
      'auditCount': Hive.box<String>('integrity_audit_reports_v1').length,
      'quarantineCount': Hive.box<String>('quarantine_documents_v1').length,
    };
  }

  static String functionalFingerprint(
    Map<String, Box<String>> boxes, {
    String? scopeNamespace,
  }) {
    final canonical = <String, dynamic>{};
    final names = qaFunctionalBootstrapBoxes.where(boxes.containsKey).toList()
      ..sort();
    for (final name in names) {
      final entries = boxes[name]!.toMap().entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      canonical[name] = {
        for (final entry in entries) '${entry.key}': _canonicalRaw(entry.value),
      };
    }
    final physical = <String, Object?>{};
    final photos = boxes['inspection_photos_v1'];
    if (photos != null) {
      for (final entry in photos.toMap().entries) {
        try {
          final photo = InspectionPhoto.fromJson(
            Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
          );
          final file = File(photo.localPath);
          final exists = file.existsSync();
          physical['${entry.key}'] = {
            'path': photo.localPath,
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
    }
    canonical['physicalPhotos'] = physical;
    canonical['scopeNamespace'] = scopeNamespace;
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(canonical))))
        .toString();
  }

  static Object? _canonicalRaw(String raw) {
    try {
      return _canonicalize(jsonDecode(raw));
    } on FormatException {
      return raw;
    }
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static String _sanitizedKey(Object key) =>
      'sha256:${sha256.convert(utf8.encode('$key')).toString().substring(0, 16)}';

  static String? _valueHash(String? value) => value == null
      ? null
      : sha256
            .convert(utf8.encode(jsonEncode(_canonicalRaw(value))))
            .toString();
}
