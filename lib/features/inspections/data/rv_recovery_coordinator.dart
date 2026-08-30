import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/f02a_scoped_identity.dart';
import '../../../data/local/visual_inspection_repository.dart';
import '../../../domain/enums/app_enums.dart';
import '../../../domain/inspections/visual_inspection.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_recovery_policy.dart';
import '../domain/rv_sync_state.dart';
import 'rv_draft_repository.dart';

const rvRecoverySchemaVersion = 1;

class RvRecoveryResult {
  const RvRecoveryResult({
    required this.runId,
    required this.documents,
    required this.meaningfulDrafts,
    required this.canonicalDrafts,
    required this.supersededEmptyDrafts,
    required this.retryStormsStopped,
  });

  final String runId;
  final int documents;
  final int meaningfulDrafts;
  final int canonicalDrafts;
  final int supersededEmptyDrafts;
  final int retryStormsStopped;
}

class RvRecoveryCoordinator {
  const RvRecoveryCoordinator({
    required this.visualRepository,
    required this.drafts,
    required this.recoveryBox,
    required this.snapshotBox,
    required this.indexBox,
    required this.syncQueueBox,
    required this.photoBox,
    required this.mediaQueueBox,
  });

  final VisualInspectionRepository visualRepository;
  final RvDraftRepository drafts;
  final Box<String> recoveryBox;
  final Box<String> snapshotBox;
  final Box<String> indexBox;
  final Box<String> syncQueueBox;
  final Box<String> photoBox;
  final Box<String> mediaQueueBox;

  static Future<void> _serializedTail = Future<void>.value();

  Future<RvRecoveryResult> runLocal() {
    final previous = _serializedTail;
    final released = Completer<void>();
    _serializedTail = released.future;
    return () async {
      await previous;
      try {
        return await _runLocal();
      } finally {
        released.complete();
      }
    }();
  }

  Future<RvRecoveryResult> _runLocal() async {
    final existing = recoveryBox.get('current');
    final resumed = existing == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(existing) as Map);
    final all = drafts.all();
    final before = _counts(all);
    final stateFingerprintBefore = _stateFingerprint();
    final groups = <String, List<RvDraft>>{};
    for (final draft in all) {
      final inspection = visualRepository.findById(draft.clientInspectionId);
      final owner = inspection?.createdBy.isNotEmpty == true
          ? inspection!.createdBy
          : draft.fieldSessionId;
      final key =
          '$owner\u0000${draft.originalAccountNumber.trim().toUpperCase()}';
      groups.putIfAbsent(key, () => []).add(draft);
    }
    final canonicalByIndexKey = <String, String>{};
    final retryUpdates = <RvDraft>[];
    final supersedeUpdates = <RvDraft>[];
    final actions = <Map<String, Object?>>[];
    for (final group in groups.values) {
      final canonical = selectCanonicalDraft(group);
      final canonicalInspection = visualRepository.findById(
        canonical.clientInspectionId,
      );
      final archiveState = canonicalInspection?.unknownFields['archiveState']
          ?.toString();
      if (!canonical.isReadOnly &&
          canonicalInspection?.status != InspectionStatus.completed &&
          canonical.localStatus != RvLocalStatus.cancelled &&
          archiveState != 'archived' &&
          canonical.supersededBy == null &&
          canonical.recoveryStatus != 'superseded_empty') {
        canonicalByIndexKey[_activeIndexKey(canonical, canonicalInspection)] =
            canonical.clientInspectionId;
      }
      for (final draft in group) {
        if (draft.clientInspectionId == canonical.clientInspectionId) {
          if (draft.retryCount >= 8 &&
              (draft.retryCount != 8 ||
                  draft.recoveryStatus != 'requiresRemoteReconciliation' ||
                  draft.canonicalReason !=
                      'highest_meaningful_evidence_score' ||
                  draft.nextRetryAt != null)) {
            retryUpdates.add(
              draft.copyWith(
                retryCount: 8,
                recoveryStatus: 'requiresRemoteReconciliation',
                canonicalReason: 'highest_meaningful_evidence_score',
                clearNextRetryAt: true,
              ),
            );
          }
          continue;
        }
        if (!hasMeaningfulLocalData(draft) &&
            hasMeaningfulLocalData(canonical) &&
            (draft.supersededBy != canonical.clientInspectionId ||
                draft.recoveryStatus != 'superseded_empty' ||
                draft.canonicalReason !=
                    'empty_duplicate_of_meaningful_draft' ||
                draft.nextRetryAt != null)) {
          supersedeUpdates.add(
            draft.copyWith(
              supersededBy: canonical.clientInspectionId,
              recoveryStatus: 'superseded_empty',
              canonicalReason: 'empty_duplicate_of_meaningful_draft',
              clearNextRetryAt: true,
            ),
          );
          actions.add({
            'action': 'supersedeEmptyDraft',
            'draft': draft.clientInspectionId,
            'supersededBy': canonical.clientInspectionId,
          });
        }
      }
    }
    final indexChanged = !_activeIndexMatches(canonicalByIndexKey);
    final resuming = resumed?['status'] == 'running';
    final completedFingerprint = resumed?['stateFingerprint']?.toString();
    final stateChanged =
        resumed?['status'] == 'completed' &&
        completedFingerprint != stateFingerprintBefore;
    final hasWork =
        resuming ||
        retryUpdates.isNotEmpty ||
        supersedeUpdates.isNotEmpty ||
        indexChanged ||
        stateChanged;
    if (!hasWork) {
      return RvRecoveryResult(
        runId: resumed?['runId']?.toString() ?? 'no-op',
        documents: all.length,
        meaningfulDrafts: before['meaningfulDrafts']! as int,
        canonicalDrafts: canonicalByIndexKey.length,
        supersededEmptyDrafts: 0,
        retryStormsStopped: 0,
      );
    }

    final runId = resuming ? '${resumed!['runId']}' : const Uuid().v4();
    final startedAt =
        resumed?['startedAt'] ?? DateTime.now().toUtc().toIso8601String();
    await recoveryBox.put(
      'current',
      jsonEncode({
        'recoverySchemaVersion': rvRecoverySchemaVersion,
        'runId': runId,
        'phase': 'prepare',
        'startedAt': startedAt,
        'status': 'running',
        'originalCounts': before,
      }),
    );
    if (!snapshotBox.containsKey(runId)) {
      await snapshotBox.put(
        runId,
        jsonEncode({
          'documents': {
            for (final e in visualRepository.documents.toMap().entries)
              '${e.key}': e.value,
          },
          'index': {
            for (final e in indexBox.toMap().entries) '${e.key}': e.value,
          },
          'queues': {
            for (final e in syncQueueBox.toMap().entries) '${e.key}': e.value,
          },
          'photoMetadata': {
            for (final e in photoBox.toMap().entries) '${e.key}': e.value,
          },
          'mediaQueue': {
            for (final e in mediaQueueBox.toMap().entries) '${e.key}': e.value,
          },
          'stateFingerprintBefore': stateFingerprintBefore,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (!snapshotBox.containsKey(runId)) {
        throw StateError(
          'No fue posible confirmar el snapshot de recuperación.',
        );
      }
    }
    for (final draft in retryUpdates) {
      await drafts.save(draft);
    }
    for (final draft in supersedeUpdates) {
      await drafts.save(draft);
    }
    if (indexChanged) await _replaceManagedActiveIndex(canonicalByIndexKey);
    if (stateChanged) {
      actions.add({
        'action': 'recordMaterialStateChange',
        'previousFingerprint': completedFingerprint,
        'currentFingerprint': stateFingerprintBefore,
      });
    }
    final afterDrafts = drafts.all();
    final after = _counts(afterDrafts);
    if ((after['documents'] as int) < (before['documents'] as int) ||
        (after['answers'] as int) < (before['answers'] as int) ||
        (after['photoReferences'] as int) <
            (before['photoReferences'] as int) ||
        (after['meaningfulDrafts'] as int) <
            (before['meaningfulDrafts'] as int)) {
      throw StateError('La verificación de no pérdida del recovery falló.');
    }
    await recoveryBox.put(
      'current',
      jsonEncode({
        'recoverySchemaVersion': rvRecoverySchemaVersion,
        'runId': runId,
        'phase': 'commit',
        'startedAt': startedAt,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'originalCounts': before,
        'resultCounts': after,
        'actions': actions,
        'stateFingerprint': _stateFingerprint(),
        'needsRemoteReconciliation': true,
      }),
    );
    return RvRecoveryResult(
      runId: runId,
      documents: all.length,
      meaningfulDrafts: before['meaningfulDrafts']! as int,
      canonicalDrafts: canonicalByIndexKey.length,
      supersededEmptyDrafts: supersedeUpdates.length,
      retryStormsStopped: retryUpdates.length,
    );
  }

  String _stateFingerprint() {
    final photoFiles = <String, Object?>{};
    for (final entry in photoBox.toMap().entries) {
      try {
        final value = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
        final path = value['localPath']?.toString();
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        final exists = file.existsSync();
        photoFiles['${entry.key}'] = {
          'path': path,
          'exists': exists,
          if (exists) 'length': file.lengthSync(),
          if (exists)
            'modifiedMicros': file
                .lastModifiedSync()
                .toUtc()
                .microsecondsSinceEpoch,
        };
      } on Object {
        photoFiles['${entry.key}'] = const {'metadataReadable': false};
      }
    }
    final state = {
      'scopeNamespace': visualRepository.accessScopeNamespace,
      'documents': _canonicalBox(visualRepository.documents),
      'index': _canonicalBox(indexBox),
      'queues': _canonicalBox(syncQueueBox),
      'photoMetadata': _canonicalBox(photoBox),
      'photoFiles': photoFiles,
      'mediaQueue': _canonicalBox(mediaQueueBox),
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(state))))
        .toString();
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

  bool _activeIndexMatches(Map<String, String> expected) {
    final actual = _managedActiveIndex(expected);
    if (actual.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, String> _managedActiveIndex(Map<String, String> expected) {
    final actual = <String, String>{};
    for (final entry in indexBox.toMap().entries) {
      final key = '${entry.key}';
      if (!key.endsWith(':f02A') && !key.endsWith('/f02A')) continue;
      if (visualRepository.accessScopeConfigured &&
          !expected.containsKey(key) &&
          visualRepository.findById(entry.value) == null) {
        continue;
      }
      actual[key] = entry.value;
    }
    return actual;
  }

  Future<void> _replaceManagedActiveIndex(Map<String, String> expected) async {
    final managed = _managedActiveIndex(expected);
    // Persist the scoped replacement before deleting the owned legacy key.
    // Interrupted migrations therefore converge with duplicate safe indexes
    // instead of making an active review unreachable.
    for (final entry in expected.entries) {
      if (indexBox.get(entry.key) == entry.value) continue;
      await indexBox.put(entry.key, entry.value);
      if (indexBox.get(entry.key) != entry.value) {
        throw StateError('No fue posible confirmar la escritura del índice.');
      }
    }
    for (final key in managed.keys) {
      if (expected.containsKey(key)) continue;
      await indexBox.delete(key);
      if (indexBox.containsKey(key)) {
        throw StateError('No fue posible confirmar el retiro del índice.');
      }
    }
  }

  Map<String, Object> _counts(List<RvDraft> values) => {
    'documents': visualRepository.documents.length,
    'drafts': values.length,
    'answers': values.fold<int>(0, (sum, draft) => sum + draft.answers.length),
    'photoReferences': values.fold<int>(
      0,
      (sum, draft) => sum + draft.photoCount,
    ),
    'physicalPhotoMetadata': photoBox.length,
    'meaningfulDrafts': values.where(hasMeaningfulLocalData).length,
  };

  String _activeIndexKey(RvDraft draft, VisualInspection? inspection) {
    final rawScope = inspection?.unknownFields['dataScope'];
    if (rawScope is Map) {
      final scope = Map<String, dynamic>.from(rawScope);
      final scopedKey = buildF02AScopedKey(
        environment: scope['environment']?.toString(),
        accountId: scope['accountId']?.toString(),
        ownerUserId: scope['ownerUserId']?.toString(),
        createdBy: inspection?.createdBy,
        inspectorId: inspection?.inspectorId,
        hydrantId: draft.hydrantId,
      );
      if (scopedKey != null) return scopedKey;
    }
    return '${draft.hydrantId}:f02A';
  }
}
