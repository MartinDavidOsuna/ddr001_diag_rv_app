import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../data/local/integrity_audit_service.dart';
import '../data/local/media_reconciliation_service.dart';
import '../data/local/operation_journal_repository.dart';
import '../data/local/quarantine_repository.dart';
import '../data/local/recovery_coordinator.dart';
import '../data/local/visual_inspection_repository.dart';
import '../features/inspections/data/rv_draft_repository.dart';
import '../features/inspections/data/rv_recovery_coordinator.dart';

typedef LocalRecoveryStageObserver =
    void Function(String stage, Duration elapsed);
typedef LocalRecoveryStageStartObserver = void Function(String stage);

class LocalRecoveryPipelineResult {
  const LocalRecoveryPipelineResult({
    required this.mediaIssues,
    required this.recoveredPhotoReferences,
    required this.rvRecovery,
  });

  final int mediaIssues;
  final int recoveredPhotoReferences;
  final RvRecoveryResult rvRecovery;
}

/// The shared, network-free bootstrap/recovery pipeline.
///
/// Production and the isolated QA flavor both call this implementation. All
/// storage is supplied by the caller, so QA cannot discover production boxes.
class LocalRecoveryPipeline {
  const LocalRecoveryPipeline({
    required this.visualRepository,
    required this.drafts,
    required this.operationJournalBox,
    required this.quarantineBox,
    required this.recoveryBox,
    required this.snapshotBox,
    required this.indexBox,
    required this.syncQueueBox,
    required this.photoBox,
    required this.mediaQueueBox,
    required this.integrityReportBox,
    this.onStageStarted,
    this.onStage,
  });

  final VisualInspectionRepository visualRepository;
  final RvDraftRepository drafts;
  final Box<String> operationJournalBox;
  final Box<String> quarantineBox;
  final Box<String> recoveryBox;
  final Box<String> snapshotBox;
  final Box<String> indexBox;
  final Box<String> syncQueueBox;
  final Box<String> photoBox;
  final Box<String> mediaQueueBox;
  final Box<String> integrityReportBox;
  final LocalRecoveryStageStartObserver? onStageStarted;
  final LocalRecoveryStageObserver? onStage;
  static Future<void> _serializedTail = Future<void>.value();

  Future<LocalRecoveryPipelineResult> run() {
    final previous = _serializedTail;
    final released = Completer<void>();
    _serializedTail = released.future;
    return () async {
      await previous;
      try {
        return await _runSerialized();
      } finally {
        released.complete();
      }
    }();
  }

  Future<LocalRecoveryPipelineResult> _runSerialized() async {
    final integrity = const IntegrityAuditService();
    final journal = OperationJournalRepository(operationJournalBox);
    final quarantine = QuarantineRepository(quarantineBox);

    await _stage(
      'journal-recovery-before-media',
      () => RecoveryCoordinator(
        auditService: integrity,
        journal: journal,
        quarantine: quarantine,
      ).runLightweight(),
    );
    final media = await _stage(
      'media-reconciliation',
      () => MediaReconciliationService().reconcile(),
    );
    await _stage('active-index', visualRepository.reconcileActiveIndex);
    final recoveredReferences = await _stage(
      'orphan-photo-references',
      drafts.reconcileOrphanedPhotoReferences,
    );
    await _stage(
      'journal-recovery-after-references',
      () => RecoveryCoordinator(
        auditService: integrity,
        journal: journal,
        quarantine: quarantine,
      ).runLightweight(),
    );
    final rvRecovery = await _stage(
      'rv-recovery',
      () => RvRecoveryCoordinator(
        visualRepository: visualRepository,
        drafts: drafts,
        recoveryBox: recoveryBox,
        snapshotBox: snapshotBox,
        indexBox: indexBox,
        syncQueueBox: syncQueueBox,
        photoBox: photoBox,
        mediaQueueBox: mediaQueueBox,
      ).runLocal(),
    );
    await _stage(
      'verified-photo-references',
      () => drafts.reconcileVerifiedPhotoReferences(mediaQueueBox),
    );
    await _stage(
      'integrity-audit',
      () => integrity.persistIfChanged(
        integrityReportBox,
        integrity.runLightweight(),
      ),
    );
    return LocalRecoveryPipelineResult(
      mediaIssues: media.length,
      recoveredPhotoReferences: recoveredReferences,
      rvRecovery: rvRecovery,
    );
  }

  Future<T> _stage<T>(String name, Future<T> Function() action) async {
    onStageStarted?.call(name);
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      onStage?.call(name, watch.elapsed);
    }
  }
}
