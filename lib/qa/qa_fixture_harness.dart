import 'dart:convert';
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/network/api_client.dart';
import '../core/security/local_data_scope.dart';
import '../data/local/visual_inspection_repository.dart';
import '../domain/enums/app_enums.dart';
import '../domain/inspections/visual_inspection.dart';
import '../domain/models/app_models.dart';
import '../domain/integrity/operation_journal.dart';
import '../domain/media/inspection_photo.dart';
import '../features/auth/data/field_session_models.dart';
import '../features/auth/data/session_secure_storage.dart';
import '../features/checklist/data/checklist_models.dart';
import '../features/inspections/data/inspection_remote_repository.dart';
import '../features/inspections/data/inspection_sync_coordinator.dart';
import '../features/inspections/data/rv_draft_repository.dart';
import '../features/inspections/domain/rv_draft.dart';
import '../features/inspections/domain/rv_sync_state.dart';
import '../features/inspections/presentation/rv_inspection_controller.dart';
import 'qa_fixture_catalog.dart';
import 'qa_app_config.dart';
import 'qa_bootstrap_lab.dart';
import 'qa_network_policy.dart';

class QaFixtureHarness {
  QaFixtureHarness._({
    required this.catalog,
    required this.drafts,
    required this.visualRepository,
    required this.coordinator,
    required this._sequenceBox,
    required this.bootstrapLab,
  });

  static const scope = LocalDataScope(
    environment: 'qa',
    accountId: 'qa-fixtures',
    userId: 'qa-user',
    brigadeId: 'qa-brigade',
    role: 'field',
  );
  static const user = AppUser(
    id: 'qa-user',
    fullName: 'Técnico QA sintético',
    email: 'qa@example.invalid',
    role: 'field',
    brigadeId: 'qa-brigade',
    brigadeName: 'QA aislado',
    deviceId: 'qa-device',
  );
  static final checklist = DynamicChecklist(
    id: 'qa-checklist-inactive-v1',
    code: 'QA-RV-INACTIVE',
    version: 1,
    title: 'Flujo QA sin hidrante',
    sections: const [],
    etag: 'qa-fixture-v1',
    cachedAt: DateTime.utc(2026, 8, 28),
  );

  final QaFixtureCatalog catalog;
  final RvDraftRepository drafts;
  final VisualInspectionRepository visualRepository;
  final InspectionSyncCoordinator coordinator;
  final Box<String> _sequenceBox;
  final QaBootstrapLab bootstrapLab;

  static Future<QaFixtureHarness> open(QaAppConfig config) async {
    if (!config.isQa || !config.fixtureMode || config.syncEnabled) {
      throw StateError('Configuración QA no segura.');
    }
    await Hive.initFlutter('ddr001_rv_qa_v1');
    final inspectionBox = await Hive.openBox<String>('visual_inspections_v1');
    final indexBox = await Hive.openBox<String>('active_inspection_index_v1');
    final photoBox = await Hive.openBox<String>('inspection_photos_v1');
    final mediaBox = await Hive.openBox<String>('media_sync_queue');
    final workBox = await Hive.openBox<String>('media_work_queue_v1');
    await Hive.openBox<String>('operation_journal_v1');
    await Hive.openBox<String>('quarantine_documents_v1');
    await Hive.openBox<String>('integrity_audit_reports_v1');
    await Hive.openBox<String>('rv_recovery_v1');
    await Hive.openBox<String>('rv_recovery_snapshots_v1');
    await Hive.openBox<String>('sync_queue');
    for (final name in qaBootstrapSupportBoxes) {
      await Hive.openBox<String>(name);
    }
    final sequenceBox = await Hive.openBox<String>('qa_fixture_runtime_v1');
    final catalog = await QaFixtureCatalog.open();
    final visual = VisualInspectionRepository(
      documents: inspectionBox,
      index: indexBox,
    )..setAccessScope(scope);
    final drafts = RvDraftRepository(visual);
    final client = ApiClient(
      config: config.apiClientConfig,
      sessionStorage: _QaNoCredentialSessionStorage(),
    );
    QaNetworkPolicy.install(client.dio, config);
    final coordinator = InspectionSyncCoordinator(
      drafts: drafts,
      remote: InspectionRemoteRepository(client),
      photoBox: photoBox,
      mediaQueue: mediaBox,
      mediaWorkQueue: workBox,
      appVersion: 'qa',
      appBuild: 'qa',
      gitSha: 'qa-local-build',
      buildDateUtc: 'qa-local-build',
    );
    final bootstrapLab = QaBootstrapLab(
      visualRepository: visual,
      drafts: drafts,
      runtimeBox: sequenceBox,
    );
    return QaFixtureHarness._(
      catalog: catalog,
      drafts: drafts,
      visualRepository: visual,
      coordinator: coordinator,
      sequenceBox: sequenceBox,
      bootstrapLab: bootstrapLab,
    );
  }

  Future<RvInspectionController> activeController() async {
    var sequence = int.tryParse(_sequenceBox.get('cameraSequence') ?? '') ?? 1;
    while (visualRepository.findById(_reviewId(sequence)) != null &&
        drafts.find(_reviewId(sequence))?.isReadOnly == true) {
      sequence++;
    }
    if (_sequenceBox.get('cameraSequence') != '$sequence') {
      await _sequenceBox.put('cameraSequence', '$sequence');
    }
    return _controllerFor(sequence);
  }

  Future<RvInspectionController> createNextController() async {
    final current = int.tryParse(_sequenceBox.get('cameraSequence') ?? '') ?? 1;
    final next = current + 1;
    await _sequenceBox.put('cameraSequence', '$next');
    return _controllerFor(next);
  }

  Future<void> resetQaFixtures() async {
    final documents = Hive.box<String>('visual_inspections_v1');
    final reviewIds = documents.keys
        .map((key) => '$key')
        .where((key) => key.startsWith('qa-review-'))
        .toSet();
    final photos = Hive.box<String>('inspection_photos_v1');
    final photoIds = <String>{};
    final photoPaths = <String>{};
    for (final entry in photos.toMap().entries) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (!reviewIds.contains(photo.inspectionId)) continue;
        photoIds.add('${entry.key}');
        photoPaths.addAll({photo.localPath, photo.thumbnailPath});
      } on Object {
        throw StateError(
          'Fixture QA ilegible; reset cancelado sin asumir identidad.',
        );
      }
    }
    final journal = Hive.box<String>('operation_journal_v1');
    final journalIds = <Object>[];
    for (final entry in journal.toMap().entries) {
      try {
        final operation = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (operation.actor == user.id ||
            operation.entityIds.any(reviewIds.contains)) {
          journalIds.add(entry.key);
        }
      } on Object {
        throw StateError('Journal QA ilegible; reset cancelado.');
      }
    }
    final index = Hive.box<String>('active_inspection_index_v1');
    final indexKeys = index
        .toMap()
        .entries
        .where((entry) => reviewIds.contains(entry.value))
        .map((entry) => entry.key)
        .toList();
    await documents.deleteAll(reviewIds);
    await index.deleteAll(indexKeys);
    await photos.deleteAll(photoIds);
    await Hive.box<String>('media_work_queue_v1').deleteAll(photoIds);
    await Hive.box<String>('media_sync_queue').deleteAll(photoIds);
    await journal.deleteAll(journalIds);
    for (final path in photoPaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    for (final name in const [
      'rv_recovery_v1',
      'rv_recovery_snapshots_v1',
      'integrity_audit_reports_v1',
      'quarantine_documents_v1',
    ]) {
      final box = Hive.box<String>(name);
      await box.deleteAll(box.keys.toList());
    }
    await _sequenceBox.deleteAll(
      _sequenceBox.keys
          .where(
            (key) =>
                key == 'cameraSequence' ||
                '$key'.startsWith('bootstrapReport:'),
          )
          .toList(),
    );
    await catalog.resetSyntheticFixtures();
  }

  Future<RvInspectionController> _controllerFor(int sequence) async {
    final hydrant = _hydrant(sequence);
    final reviewId = _reviewId(sequence);
    if (visualRepository.findById(reviewId) == null) {
      await _seedReview(reviewId: reviewId, hydrant: hydrant);
    }
    final controller = RvInspectionController(
      drafts: drafts,
      coordinator: coordinator,
      hydrant: hydrant,
      user: user,
      checklist: checklist,
    );
    await controller.initialize();
    return controller;
  }

  Future<void> _seedReview({
    required String reviewId,
    required Hydrant hydrant,
  }) async {
    final now = DateTime.now().toUtc();
    final draft = RvDraft(
      clientInspectionId: reviewId,
      hydrantId: hydrant.id,
      accountNumber: hydrant.code,
      fieldSessionId: user.id,
      checklistId: checklist.id,
      checklistVersion: checklist.version,
      checklistSnapshot: checklist.toJson(),
      createdAt: now,
      updatedAt: now,
      location: RvLocationSample(
        latitude: 1.0,
        longitude: -1.0,
        horizontalAccuracy: 5,
        source: 'qa_fixture',
        capturedAt: now,
      ),
      locationStatus: RvPartStatus.pending,
      localStatus: RvLocalStatus.pendingLocation,
    );
    final inspection = VisualInspection(
      id: reviewId,
      hydrantId: hydrant.id,
      source: HydrantSource.assigned,
      inspectorId: user.id,
      inspectorName: user.fullName,
      brigadeId: user.brigadeId,
      brigadeName: user.brigadeName,
      deviceId: user.deviceId,
      startedAt: now,
      createdAt: now,
      createdBy: user.id,
      updatedAt: now,
      updatedBy: user.id,
      identification: HydrantIdentification(assignedCode: hydrant.code),
      unknownFields: {
        RvDraftRepository.storageKey: draft.toJson(),
        'dataScope': {
          'environment': scope.environment,
          'accountId': scope.accountId,
          'ownerUserId': scope.userId,
          'brigadeId': scope.brigadeId,
        },
        'qaFixture': true,
      },
    );
    await visualRepository.save(inspection);
    await visualRepository.index.put(
      '${scope.namespace}/${hydrant.id}/f02A',
      reviewId,
    );
  }

  static String _reviewId(int sequence) =>
      'qa-review-camera-${sequence.toString().padLeft(4, '0')}';

  static Hydrant _hydrant(int sequence) => Hydrant(
    id: 'qa-hydrant-camera-${sequence.toString().padLeft(4, '0')}',
    code: 'QA-CAMERA-${sequence.toString().padLeft(4, '0')}',
    locality: 'Ubicación sintética',
    parcel: 'Fixture QA',
    priority: PriorityLevel.low,
    access: AccessType.vehicle,
    syncStatus: SyncStatus.local,
    f02a: const InspectionSummary(
      type: InspectionType.f02A,
      status: InspectionStatus.inProgress,
      progress: 0,
    ),
    f02b: const InspectionSummary(
      type: InspectionType.f02B,
      status: InspectionStatus.notRequired,
      progress: 0,
    ),
    latitude: 1,
    longitude: -1,
  );
}

class _QaNoCredentialSessionStorage implements SessionStorage {
  String? _installationId;

  @override
  Future<void> clear() async {}

  @override
  Future<String> installationId() async =>
      _installationId ??= 'qa-installation-offline';

  @override
  Future<FieldSession?> read() async => null;

  @override
  Future<void> save(FieldSession session) async {
    throw StateError('QA no guarda credenciales.');
  }
}
