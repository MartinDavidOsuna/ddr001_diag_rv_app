import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock/demo_data.dart';
import '../../data/services/mock_assignment_sync_service.dart';
import '../../data/local/visual_inspection_repository.dart';
import '../../data/local/functional_repositories.dart';
import '../../data/local/sync_queue_repository.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/media/inspection_photo.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/enums/hydrant_list_filter.dart';
import '../../domain/filters/hydrant_filter_request.dart';
import '../../domain/filters/hydrant_query_projection.dart';
import '../../domain/models/app_models.dart';
import '../../domain/models/assignment_sync_models.dart';
import '../../domain/functional/functional_models.dart';
import '../../domain/sync/sync_queue_item.dart';
import 'update_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.preferences,
    required this.traceBox,
    required this.syncBox,
    required this.mediaBox,
    required this.syncedTraceBox,
    required this.packageInfo,
    required this.visualInspectionRepository,
    required this.functionalEligibilityRepository,
    required this.functionalInspectionRepository,
  });
  final SharedPreferences preferences;
  final Box<String> traceBox, syncBox, mediaBox, syncedTraceBox;
  final PackageInfo packageInfo;
  final VisualInspectionRepository visualInspectionRepository;
  final FunctionalEligibilityRepository functionalEligibilityRepository;
  final FunctionalInspectionRepository functionalInspectionRepository;
  late final SyncQueueRepository syncQueueRepository = SyncQueueRepository(
    syncBox,
  );
  final updateService = UpdateService(remoteManifestUrl: '');
  final assignmentSyncService = MockAssignmentSyncService();
  final user = demoUser;
  late final List<Hydrant> hydrants = List<Hydrant>.of(demoHydrants);
  final Set<String> assignmentsForReview = {};
  bool initialized = false,
      online = true,
      syncing = false,
      assignmentSyncing = false;
  double syncProgress = 0;
  UpdateInfo? updateInfo;
  UpdateDemoScenario updateDemoScenario = UpdateDemoScenario.current;
  AssignmentSyncScenario assignmentScenario = AssignmentSyncScenario.noChanges;
  AssignmentSyncResult? lastAssignmentResult;
  DateTime? lastAssignmentCheck;
  String? assignmentError, assignmentCursor;
  HydrantListFilter hydrantListFilter = HydrantListFilter.all;
  HydrantFilterRequest? hydrantFilterRequest;
  int _hydrantFilterRequestSequence = 0;

  bool get authenticated => preferences.getBool('demo_session') ?? false;
  String get versionLabel =>
      '${packageInfo.version}+${packageInfo.buildNumber}';
  int get installedBuild => int.tryParse(packageInfo.buildNumber) ?? 0;
  bool get editingRestricted => updateInfo?.status == UpdateStatus.required;
  int get pendingDiagnostics =>
      syncQueueRepository
          .all()
          .where((item) => item.status != SyncQueueStatus.synced)
          .length +
      syncQueueRepository.unreadableCount;
  int get pendingPhotos =>
      mediaBox.values.where((v) => v != MediaSyncStatus.verified.name).length;
  int get verifiedPhotos =>
      mediaBox.values.where((v) => v == MediaSyncStatus.verified.name).length;
  int get pendingTrace =>
      traceBox.keys.where((key) => !syncedTraceBox.containsKey('$key')).length;
  int get syncErrors => mediaBox.values
      .where(
        (v) => {
          MediaSyncStatus.failedRetryable.name,
          MediaSyncStatus.failedPermanent.name,
          MediaSyncStatus.missingLocal.name,
          MediaSyncStatus.remoteMissing.name,
        }.contains(v),
      )
      .length;
  int get pendingCount => pendingDiagnostics + pendingPhotos + pendingTrace;
  bool get allSynchronized =>
      pendingDiagnostics == 0 &&
      pendingPhotos == 0 &&
      pendingTrace == 0 &&
      syncErrors == 0;

  Future<void> initialize() async {
    for (final hydrant in hydrants.where(
      (value) => value.f02b.status != InspectionStatus.notRequired,
    )) {
      if (functionalEligibilityRepository.find(hydrant.id) == null) {
        final now = DateTime.now().toUtc();
        await functionalEligibilityRepository.save(
          FunctionalReportEligibility(
            hydrantId: hydrant.id,
            allowed: true,
            source: FunctionalEligibilitySource.demo,
            reason: 'Habilitación DEMO de asignación local',
            authorizedBy: user.id,
            authorizedRole: user.role,
            deviceId: user.deviceId,
            authorizedAt: now,
            pendingValidation: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }
    if (syncBox.isEmpty) {
      await syncBox.put('DDR001-HID-0002', 'Guardado localmente');
      await syncBox.put('DDR001-HID-0491', 'Guardado localmente');
    }
    if (!(preferences.getBool('media_demo_seeded') ?? false)) {
      await mediaBox.put('PHOTO-DEMO-001', MediaSyncStatus.pendingUpload.name);
      await mediaBox.put(
        'PHOTO-DEMO-002',
        MediaSyncStatus.uploadedUnverified.name,
      );
      await preferences.setBool('media_demo_seeded', true);
    }
    updateInfo = await updateService.check(
      installedVersion: packageInfo.version,
      installedBuild: installedBuild,
    );
    initialized = true;
    notifyListeners();
  }

  Future<bool> login(
    String email,
    String password, {
    required bool remember,
  }) async {
    final valid =
        email.trim().toLowerCase() == 'inspector.demo@ddr001.mx' &&
        password == 'demo123';
    if (!valid) {
      return false;
    }
    await preferences.setBool('demo_session', true);
    await preferences.setBool('remember_session', remember);
    await trace('login', 'Inicio de sesión demo');
    await checkConfiguredManifest(manual: false);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await trace('logout', 'Cierre de sesión');
    await preferences.setBool('demo_session', false);
    notifyListeners();
  }

  void toggleConnection() {
    online = !online;
    notifyListeners();
  }

  void setHydrantListFilter(HydrantListFilter value) {
    hydrantListFilter = value;
    hydrantFilterRequest = null;
    notifyListeners();
  }

  void requestHydrantListFilterFromHome(HydrantListFilter value) {
    hydrantListFilter = value;
    hydrantFilterRequest = HydrantFilterRequest(
      id: 'home-${++_hydrantFilterRequestSequence}',
      filter: value,
      source: HydrantFilterRequestSource.home,
      createdAt: DateTime.now().toUtc(),
    );
    notifyListeners();
  }

  void consumeHydrantFilterRequest(String requestId) {
    if (hydrantFilterRequest?.id != requestId) return;
    hydrantFilterRequest = null;
  }

  void clearHydrantListFilter() {
    hydrantListFilter = HydrantListFilter.all;
    hydrantFilterRequest = null;
    notifyListeners();
  }

  List<Hydrant> hydrantsForFilter(HydrantListFilter filter) => hydrants
      .where(
        (hydrant) =>
            HydrantQueryProjection.matches(filter, _filterFacts(hydrant)),
      )
      .toList(growable: false);

  int hydrantCountForFilter(HydrantListFilter filter) =>
      hydrantsForFilter(filter).length;

  HydrantFilterFacts _filterFacts(Hydrant hydrant) {
    final functional = functionalSummary(hydrant.id);
    final activeFunctional = functionalInspectionRepository.activeFor(
      hydrant.id,
    );
    final functionalHistory = functionalInspectionRepository.forHydrant(
      hydrant.id,
    );
    final eligibility = functionalEligibilityRepository.find(hydrant.id);
    final visualInProgress =
        hydrant.f02a.status == InspectionStatus.inProgress ||
        visualInspectionRepository.hasLocalInspection(hydrant.id);
    final functionalInProgress =
        activeFunctional != null &&
        activeFunctional.status != FunctionalInspectionStatus.completed &&
        activeFunctional.status != FunctionalInspectionStatus.cancelled &&
        activeFunctional.status != FunctionalInspectionStatus.synced;
    final functionalCompleted =
        functional.status == InspectionStatus.completed ||
        functionalHistory.any(
          (value) => value.status == FunctionalInspectionStatus.completed,
        );
    return HydrantFilterFacts(
      visualAvailable:
          hydrant.f02a.status != InspectionStatus.notRequired ||
          visualInspectionRepository.hasLocalInspection(hydrant.id),
      functionalAvailable:
          eligibility?.allowed == true ||
          activeFunctional != null ||
          functionalHistory.isNotEmpty ||
          hydrant.f02b.status != InspectionStatus.notRequired,
      visualInProgress: visualInProgress,
      functionalInProgress: functionalInProgress,
      visualCompleted: hydrant.f02a.status == InspectionStatus.completed,
      functionalCompleted: functionalCompleted,
      unsynchronized: _hasUnsynchronizedData(hydrant),
      visualPending: hydrant.f02a.status == InspectionStatus.pending,
      functionalPending: functional.status == InspectionStatus.pending,
      functionalRequired:
          eligibility?.allowed == true ||
          functional.status != InspectionStatus.notRequired,
      functionalSuspended:
          activeFunctional?.status == FunctionalInspectionStatus.suspended,
      functionalFailed:
          activeFunctional?.stepData.values.contains('failed') == true,
      pendingValidation:
          hydrant.source == HydrantSource.fieldCreated ||
          eligibility?.pendingValidation == true,
      hasIncidents:
          hydrant.damageCount > 0 || assignmentsForReview.contains(hydrant.id),
    );
  }

  bool _hasUnsynchronizedData(Hydrant hydrant) {
    if (hydrant.syncStatus != SyncStatus.synced) return true;
    for (final entry in syncBox.toMap().entries) {
      final raw = entry.value;
      if (raw == 'Sincronizado') continue;
      if ('${entry.key}' == hydrant.id || '${entry.key}' == hydrant.code) {
        return true;
      }
      try {
        final item = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (item.hydrantId == hydrant.id &&
            item.status != SyncQueueStatus.synced) {
          return true;
        }
      } on Object {
        continue;
      }
    }
    final photos = Hive.box<String>('inspection_photos_v1');
    for (final raw in photos.values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (photo.hydrantId == hydrant.id &&
            mediaBox.get(photo.id) != MediaSyncStatus.verified.name) {
          return true;
        }
      } on Object {
        continue;
      }
    }
    for (final entry in traceBox.toMap().entries) {
      if (syncedTraceBox.containsKey('${entry.key}')) continue;
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(entry.value) as Map,
        );
        if (payload['hydrantId'] == hydrant.id) return true;
      } on Object {
        continue;
      }
    }
    return false;
  }

  Hydrant hydrant(String id) => hydrants.firstWhere((item) => item.id == id);

  InspectionSummary functionalSummary(String hydrantId) {
    final active = functionalInspectionRepository.activeFor(hydrantId);
    if (active != null) {
      final status = switch (active.status) {
        FunctionalInspectionStatus.completed => InspectionStatus.completed,
        FunctionalInspectionStatus.draft => InspectionStatus.pending,
        _ => InspectionStatus.inProgress,
      };
      return InspectionSummary(
        type: InspectionType.f02B,
        status: status,
        progress: active.progress,
      );
    }
    final history = functionalInspectionRepository.forHydrant(hydrantId);
    if (history.any(
      (value) => value.status == FunctionalInspectionStatus.completed,
    )) {
      return const InspectionSummary(
        type: InspectionType.f02B,
        status: InspectionStatus.completed,
        progress: 1,
      );
    }
    final eligibility = functionalEligibilityRepository.find(hydrantId);
    if (eligibility?.allowed == true) {
      return const InspectionSummary(
        type: InspectionType.f02B,
        status: InspectionStatus.pending,
        progress: 0,
      );
    }
    return hydrant(hydrantId).f02b;
  }

  String functionalStateLabel(String hydrantId) {
    final active = functionalInspectionRepository.activeFor(hydrantId);
    if (active != null) {
      if (active.status == FunctionalInspectionStatus.suspended) {
        return 'RF suspendido';
      }
      if (active.status == FunctionalInspectionStatus.paused) {
        return 'RF en proceso';
      }
      if (active.status == FunctionalInspectionStatus.requiresRepeat) {
        return 'RF requiere repetición';
      }
      if (active.stepData.values.contains('failed')) return 'RF con falla';
      return active.currentStep <= 1 ? 'RF pendiente' : 'RF en proceso';
    }
    final history = functionalInspectionRepository.forHydrant(hydrantId);
    if (history.any(
      (value) => value.status == FunctionalInspectionStatus.completed,
    )) {
      return 'RF finalizado';
    }
    final eligibility = functionalEligibilityRepository.find(hydrantId);
    if (eligibility?.pendingValidation == true) {
      return 'RF pendiente de autorización';
    }
    if (eligibility?.source ==
        FunctionalEligibilitySource.requiredByVisualResult) {
      return 'RF requerido';
    }
    if (eligibility?.allowed == true) return 'RF disponible';
    return 'RF no requerido';
  }

  void markHydrantUnassigned(String id) {
    final index = hydrants.indexWhere((item) => item.id == id);
    if (index >= 0) {
      hydrants[index] = hydrants[index].copyWith(
        source: HydrantSource.unassigned,
      );
    }
    notifyListeners();
  }

  void addFieldHydrant(Hydrant value) {
    if (hydrants.any(
      (item) => item.id == value.id || item.code == value.code,
    )) {
      return;
    }
    hydrants.add(value);
    notifyListeners();
  }

  void markVisualReportCompleted(String hydrantId) {
    final index = hydrants.indexWhere((item) => item.id == hydrantId);
    if (index < 0) return;
    hydrants[index] = hydrants[index].copyWith(
      f02a: const InspectionSummary(
        type: InspectionType.f02A,
        status: InspectionStatus.completed,
        progress: 1,
      ),
      syncStatus: SyncStatus.pending,
    );
    notifyListeners();
  }

  Future<void> trace(
    String action,
    String description, {
    String? hydrantId,
    String? inspectionId,
    String? entityType,
    String? entityId,
    String? reason,
    Map<String, dynamic> metadata = const {},
    String? correlationId,
  }) async {
    final event = TraceEvent(
      id: const Uuid().v4(),
      action: action,
      description: description,
      createdAt: DateTime.now(),
      userId: user.id,
      brigadeName: user.brigadeName,
      deviceId: user.deviceId,
      hydrantId: hydrantId,
      inspectionId: inspectionId,
      entityType: entityType,
      entityId: entityId,
      reason: reason,
      metadata: metadata,
      correlationId: correlationId,
    );
    await traceBox.put(event.id, jsonEncode(event.toJson()));
    notifyListeners();
  }

  Future<void> enqueueSync({
    required String entityType,
    required String entityId,
    String? inspectionId,
    String? hydrantId,
    List<String> dependencyIds = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final id = '$entityType:$entityId';
    final item = SyncQueueItem(
      id: id,
      entityType: entityType,
      entityId: entityId,
      inspectionId: inspectionId,
      hydrantId: hydrantId,
      dependencyIds: dependencyIds,
      idempotencyKey: id,
      correlationId: const Uuid().v4(),
      createdAt: now,
      updatedAt: now,
    );
    await syncQueueRepository.save(item);
    notifyListeners();
  }

  Future<void> synchronize() async {
    if (!online || syncing || allSynchronized) {
      return;
    }
    syncing = true;
    syncProgress = 0;
    notifyListeners();
    await trace('sync_execute', 'Ejecución de sincronización simulada');
    final traceKeys = traceBox.keys.map((e) => '$e').toList();
    for (var i = 1; i <= 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      syncProgress = i / 8;
      notifyListeners();
    }
    final syncKeys = syncBox.keys.toList()
      ..sort((left, right) {
        int priority(Object key) {
          final raw = syncBox.get(key);
          if (raw == null) return 99;
          try {
            final item = SyncQueueItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
            return switch (item.entityType) {
              'localHydrant' => 1,
              'functionalEligibility' => 2,
              'functionalInspection' => 3,
              'instrument' => 4,
              'FunctionalValveTest' ||
              'ReducerTest' ||
              'SolenoidTest' ||
              'EnergyTest' ||
              'CommunicationTest' ||
              'AlarmTest' ||
              'LeakageTest' => 5,
              'measurementSeries' => 6,
              'measurementReading' => 7,
              'functionalResult' => 8,
              _ => 50,
            };
          } on Object {
            return 90;
          }
        }

        return priority(left).compareTo(priority(right));
      });
    for (final key in syncKeys) {
      final raw = syncBox.get(key);
      if (raw == null) continue;
      try {
        final current = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        final synced = SyncQueueItem(
          id: current.id,
          entityType: current.entityType,
          entityId: current.entityId,
          inspectionId: current.inspectionId,
          hydrantId: current.hydrantId,
          operation: current.operation,
          dependencyIds: current.dependencyIds,
          idempotencyKey: current.idempotencyKey,
          payloadVersion: current.payloadVersion,
          revision: current.revision,
          baseRevision: current.baseRevision,
          tombstone: current.tombstone,
          status: SyncQueueStatus.synced,
          attempts: current.attempts + 1,
          nextAttemptAt: current.nextAttemptAt,
          conflictStatus: current.conflictStatus,
          correlationId: current.correlationId,
          createdAt: current.createdAt,
          updatedAt: DateTime.now().toUtc(),
          schemaVersion: current.schemaVersion,
        );
        await syncBox.put(key, jsonEncode(synced.toJson()));
      } on Object {
        await syncBox.put(key, 'Sincronizado');
      }
    }
    for (final key in mediaBox.keys.toList()) {
      if (!'$key'.startsWith('PHOTO-DEMO-')) {
        continue;
      }
      final current = mediaBox.get(key);
      if ({
        MediaSyncStatus.failedRetryable.name,
        MediaSyncStatus.failedPermanent.name,
        MediaSyncStatus.missingLocal.name,
        MediaSyncStatus.remoteMissing.name,
      }.contains(current)) {
        continue;
      }
      await mediaBox.put(key, MediaSyncStatus.uploadedUnverified.name);
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await mediaBox.put(key, MediaSyncStatus.verified.name);
    }
    for (final key in traceKeys) {
      await syncedTraceBox.put(key, DateTime.now().toUtc().toIso8601String());
    }
    syncProgress = 1;
    syncing = false;
    notifyListeners();
  }

  Future<void> retryMedia(String id) async {
    await mediaBox.put(id, MediaSyncStatus.pendingUpload.name);
    notifyListeners();
    await synchronize();
  }

  Future<void> synchronizeAssignments() async {
    if (assignmentSyncing) {
      return;
    }
    assignmentSyncing = true;
    assignmentError = null;
    lastAssignmentResult = null;
    notifyListeners();
    await trace('assignment_sync_started', 'Consulta de asignaciones iniciada');
    try {
      if (!online ||
          assignmentScenario == AssignmentSyncScenario.temporaryError) {
        throw const AssignmentSyncException(
          'Error temporal de conexión. Intenta nuevamente.',
        );
      }
      final result = await assignmentSyncService.synchronize(
        scenario: assignmentScenario,
        userId: user.id,
        brigadeId: user.brigadeId,
        deviceId: user.deviceId,
        cursor: assignmentCursor,
        catalogVersion: 'demo-1',
      );
      for (final incoming in [
        ...result.newAssignments,
        ...result.updatedAssignments,
      ]) {
        final index = hydrants.indexWhere((h) => h.id == incoming.id);
        if (index < 0) {
          hydrants.add(incoming);
        } else {
          final local = hydrants[index];
          hydrants[index] = local.copyWith(
            locality: incoming.locality,
            parcel: incoming.parcel,
            priority: incoming.priority,
            syncStatus: incoming.syncStatus,
          );
        }
      }
      for (final removedId in result.removedIds) {
        final index = hydrants.indexWhere((h) => h.id == removedId);
        if (index >= 0) {
          final local = hydrants[index];
          final hasLocalWork =
              local.source == HydrantSource.fieldCreated ||
              local.f02a.progress > 0 ||
              local.f02b.progress > 0 ||
              local.photoCount > 0 ||
              syncBox.containsKey(local.code);
          if (hasLocalWork) {
            assignmentsForReview.add(removedId);
          } else {
            hydrants.removeAt(index);
          }
        }
      }
      assignmentCursor = result.nextCursor;
      lastAssignmentResult = result;
      lastAssignmentCheck = DateTime.now();
      if (result.newCount > 0) {
        await trace(
          'assignments_new',
          '${result.newCount} asignaciones nuevas',
        );
      }
      if (result.updatedCount > 0) {
        await trace(
          'assignments_updated',
          '${result.updatedCount} asignaciones actualizadas',
        );
      }
      if (result.removedCount > 0) {
        await trace(
          'assignments_removed',
          '${result.removedCount} asignaciones retiradas',
        );
      }
      if (result.newCount + result.updatedCount + result.removedCount == 0) {
        await trace('assignment_sync_no_changes', 'Consulta sin cambios');
      }
      await trace(
        'assignment_sync_finished',
        'Consulta de asignaciones finalizada',
      );
    } catch (error) {
      assignmentError = error.toString();
      lastAssignmentCheck = DateTime.now();
      await trace('assignment_sync_error', assignmentError!);
    }
    assignmentSyncing = false;
    notifyListeners();
  }

  Future<void> synchronizeNextAssignmentScenario() async {
    final values = AssignmentSyncScenario.values;
    final current = values.indexOf(assignmentScenario);
    assignmentScenario = values[(current + 1) % values.length];
    await synchronizeAssignments();
  }

  void setAssignmentScenario(AssignmentSyncScenario value) {
    assignmentScenario = value;
    notifyListeners();
  }

  Future<void> setUpdateScenario(UpdateDemoScenario value) async {
    updateDemoScenario = value;
    await checkUpdates(manual: true);
  }

  Future<void> checkUpdates({bool manual = true}) async {
    await trace(
      'update_check_started',
      'Comprobación de actualización iniciada',
    );
    updateInfo = await updateService.check(
      installedVersion: packageInfo.version,
      installedBuild: installedBuild,
      manual: manual,
      demoScenario: updateDemoScenario,
    );
    final action = switch (updateInfo!.status) {
      UpdateStatus.optional => 'update_optional_detected',
      UpdateStatus.required => 'update_required_detected',
      UpdateStatus.unavailable => 'update_check_error',
      UpdateStatus.current => 'update_current',
    };
    await trace(action, updateInfo!.title);
    notifyListeners();
  }

  Future<void> checkConfiguredManifest({bool manual = true}) async {
    await trace(
      'update_check_started',
      'Comprobación manual del manifiesto configurado',
    );
    updateDemoScenario = UpdateDemoScenario.current;
    updateInfo = await updateService.check(
      installedVersion: packageInfo.version,
      installedBuild: installedBuild,
      manual: manual,
    );
    await trace(
      updateInfo!.status == UpdateStatus.unavailable
          ? 'update_check_error'
          : 'update_manifest_checked',
      updateInfo!.title,
    );
    notifyListeners();
  }

  Future<void> postponeUpdate() =>
      trace('update_postponed', 'Actualización pospuesta');
  Future<bool> openUpdate() async {
    await trace('update_button_pressed', 'Botón actualizar pulsado');
    return updateService.openAndroidDownload(updateInfo!);
  }
}
