import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/visual_inspection_repository.dart';
import '../../../domain/inspections/visual_inspection.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_recovery_policy.dart';
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

  Future<RvRecoveryResult> runLocal() async {
    final existing = recoveryBox.get('current');
    final resumed = existing == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(existing) as Map);
    final runId = resumed?['status'] == 'running'
        ? '${resumed!['runId']}'
        : const Uuid().v4();
    final startedAt = resumed?['startedAt'] ?? DateTime.now().toUtc().toIso8601String();
    final all = drafts.all();
    final before = _counts(all);
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
    await snapshotBox.put(
      runId,
      jsonEncode({
        'documents': {for (final e in visualRepository.documents.toMap().entries) '${e.key}': e.value},
        'index': {for (final e in indexBox.toMap().entries) '${e.key}': e.value},
        'queues': {for (final e in syncQueueBox.toMap().entries) '${e.key}': e.value},
        'photoMetadata': {for (final e in photoBox.toMap().entries) '${e.key}': e.value},
        'mediaQueue': {for (final e in mediaQueueBox.toMap().entries) '${e.key}': e.value},
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    final groups = <String, List<RvDraft>>{};
    for (final draft in all) {
      final inspection = visualRepository.findById(draft.clientInspectionId);
      final owner = inspection?.createdBy.isNotEmpty == true
          ? inspection!.createdBy
          : draft.fieldSessionId;
      final key = '$owner\u0000${draft.originalAccountNumber.trim().toUpperCase()}';
      groups.putIfAbsent(key, () => []).add(draft);
    }
    final canonicalByIndexKey = <String, String>{};
    var superseded = 0;
    var retriesStopped = 0;
    final actions = <Map<String, Object?>>[];
    for (final group in groups.values) {
      final canonical = selectCanonicalDraft(group);
      final canonicalInspection = visualRepository.findById(
        canonical.clientInspectionId,
      );
      canonicalByIndexKey[_activeIndexKey(canonical, canonicalInspection)] =
          canonical.clientInspectionId;
      for (final draft in group) {
        if (draft.clientInspectionId == canonical.clientInspectionId) {
          if (draft.retryCount > 0 && draft.retryCount >= 8) {
            await drafts.save(draft.copyWith(
              retryCount: 8,
              recoveryStatus: 'requiresRemoteReconciliation',
              canonicalReason: 'highest_meaningful_evidence_score',
              clearNextRetryAt: true,
            ));
            retriesStopped++;
          }
          continue;
        }
        if (!hasMeaningfulLocalData(draft) && hasMeaningfulLocalData(canonical)) {
          await drafts.save(draft.copyWith(
            supersededBy: canonical.clientInspectionId,
            recoveryStatus: 'superseded_empty',
            canonicalReason: 'empty_duplicate_of_meaningful_draft',
            clearNextRetryAt: true,
          ));
          superseded++;
          actions.add({
            'action': 'supersedeEmptyDraft',
            'draft': draft.clientInspectionId,
            'supersededBy': canonical.clientInspectionId,
          });
        }
      }
    }
    await visualRepository.replaceActiveVisualIndex(canonicalByIndexKey);
    final afterDrafts = drafts.all();
    final after = _counts(afterDrafts);
    if ((after['documents'] as int) < (before['documents'] as int) ||
        (after['answers'] as int) < (before['answers'] as int) ||
        (after['photoReferences'] as int) < (before['photoReferences'] as int) ||
        (after['meaningfulDrafts'] as int) < (before['meaningfulDrafts'] as int)) {
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
        'needsRemoteReconciliation': true,
      }),
    );
    return RvRecoveryResult(
      runId: runId,
      documents: all.length,
      meaningfulDrafts: before['meaningfulDrafts']! as int,
      canonicalDrafts: canonicalByIndexKey.length,
      supersededEmptyDrafts: superseded,
      retryStormsStopped: retriesStopped,
    );
  }

  Map<String, Object> _counts(List<RvDraft> values) => {
    'documents': visualRepository.documents.length,
    'drafts': values.length,
    'answers': values.fold<int>(0, (sum, draft) => sum + draft.answers.length),
    'photoReferences': values.fold<int>(0, (sum, draft) => sum + draft.photoCount),
    'physicalPhotoMetadata': photoBox.length,
    'meaningfulDrafts': values.where(hasMeaningfulLocalData).length,
  };

  String _activeIndexKey(RvDraft draft, VisualInspection? inspection) {
    final rawScope = inspection?.unknownFields['dataScope'];
    if (rawScope is Map) {
      final scope = Map<String, dynamic>.from(rawScope);
      final environment = scope['environment']?.toString().trim();
      final accountId = scope['accountId']?.toString().trim();
      final owner = (scope['ownerUserId'] ?? inspection?.createdBy)
          ?.toString()
          .trim();
      if (environment?.isNotEmpty == true &&
          accountId?.isNotEmpty == true &&
          owner?.isNotEmpty == true) {
        String part(String value) => Uri.encodeComponent(value.toLowerCase());
        return '${part(environment!)}/${part(accountId!)}/${part(owner!)}/${draft.hydrantId}/f02A';
      }
    }
    return '${draft.hydrantId}:f02A';
  }
}
