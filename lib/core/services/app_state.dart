import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
import '../../features/auth/data/field_session_models.dart';
import '../../features/auth/data/field_session_repository.dart';
import '../../features/hydrants/data/hydrant_repository.dart';
import '../../features/hydrants/data/hydrant_api_models.dart';
import '../../features/checklist/data/checklist_models.dart';
import '../../features/checklist/data/checklist_repository.dart';
import '../../features/inspections/data/inspection_sync_coordinator.dart';
import '../../features/inspections/data/rv_draft_repository.dart';
import '../../features/catalogs/dynamic_catalog_repository.dart';
import '../config/app_config.dart';
import '../network/api_exception.dart';
import '../network/connectivity_monitor.dart';
import '../security/local_data_scope.dart';
import 'update_service.dart';

class ProfileTodayStats {
  const ProfileTodayStats({
    required this.date,
    required this.submitted,
    required this.pending,
    required this.unsynced,
  });

  final DateTime date;
  final int submitted;
  final int pending;
  final int unsynced;
}

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
    required this.sessionRepository,
    required this.hydrantRepository,
    required this.checklistRepository,
    required this.rvDraftRepository,
    required this.inspectionSyncCoordinator,
    this.dynamicCatalogRepository,
    this.connectivityMonitor,
  });
  final SharedPreferences preferences;
  final Box<String> traceBox, syncBox, mediaBox, syncedTraceBox;
  final PackageInfo packageInfo;
  final VisualInspectionRepository visualInspectionRepository;
  final FunctionalEligibilityRepository functionalEligibilityRepository;
  final FunctionalInspectionRepository functionalInspectionRepository;
  final FieldSessionRepository sessionRepository;
  final HydrantRepository hydrantRepository;
  final ChecklistRepository checklistRepository;
  final RvDraftRepository rvDraftRepository;
  final InspectionSyncCoordinator inspectionSyncCoordinator;
  final DynamicCatalogRepository? dynamicCatalogRepository;
  final ConnectivityMonitor? connectivityMonitor;
  late final SyncQueueRepository syncQueueRepository = SyncQueueRepository(
    syncBox,
  );
  final updateService = UpdateService(remoteManifestUrl: '');
  FieldSession? _session;
  late AppUser _user = const AppUser(
    id: 'offline',
    fullName: 'Inspector de campo',
    email: '',
    role: 'Inspector',
    brigadeId: '',
    brigadeName: '',
    deviceId: '',
  );
  AppUser get user => _user;
  final List<Hydrant> hydrants = [];
  final List<Hydrant> catalogHydrants = [];
  final Set<String> assignmentsForReview = {};
  bool initialized = false,
      online = true,
      syncing = false,
      assignmentSyncing = false;
  bool sessionOffline = false;
  double syncProgress = 0;
  UpdateInfo? updateInfo;
  AssignmentSyncScenario assignmentScenario = AssignmentSyncScenario.noChanges;
  AssignmentSyncResult? lastAssignmentResult;
  DateTime? lastAssignmentCheck;
  String? assignmentError, assignmentCursor;
  HydrantListFilter hydrantListFilter = HydrantListFilter.all;
  HydrantFilterRequest? hydrantFilterRequest;
  int _hydrantFilterRequestSequence = 0;
  ProfileTodayStats? _remoteProfileStats;
  bool profileStatsLoading = false;

  bool get authenticated => _session != null;
  NetworkAvailabilityState get connectivityState =>
      connectivityMonitor?.state ??
      (online
          ? NetworkAvailabilityState.apiAvailable
          : NetworkAvailabilityState.apiUnavailable);
  DynamicChecklist? activeChecklist;
  String? checklistError;
  DateTime? get hydrantsLastUpdated => hydrantRepository.lastUpdated;
  String get versionLabel =>
      '${packageInfo.version}+${packageInfo.buildNumber}';
  int get installedBuild => int.tryParse(packageInfo.buildNumber) ?? 0;
  bool get editingRestricted =>
      AppConfig.appUpdatesEnabled &&
      updateInfo?.status == UpdateStatus.required;
  int get pendingDiagnostics =>
      syncQueueRepository
          .all()
          .where((item) => item.status != SyncQueueStatus.synced)
          .length +
      syncQueueRepository.unreadableCount;
  Set<String> get accessiblePhotoIds {
    if (!authenticated) return const {};
    final ids = <String>{};
    final photos = Hive.box<String>('inspection_photos_v1');
    for (final raw in photos.values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (photo.capturedByUserId == user.id) ids.add(photo.id);
      } on Object {
        continue;
      }
    }
    return ids;
  }

  int get pendingPhotos => accessiblePhotoIds
      .where((id) => mediaBox.get(id) != MediaSyncStatus.verified.name)
      .length;
  int get verifiedPhotos => accessiblePhotoIds
      .where((id) => mediaBox.get(id) == MediaSyncStatus.verified.name)
      .length;
  int get pendingTrace {
    if (!authenticated) return 0;
    var count = 0;
    for (final entry in traceBox.toMap().entries) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(entry.value) as Map,
        );
        if (payload['userId'] == user.id &&
            !syncedTraceBox.containsKey('${entry.key}')) {
          count++;
        }
      } on Object {
        continue;
      }
    }
    return count;
  }

  int get syncErrors => accessiblePhotoIds
      .map(mediaBox.get)
      .where(
        (v) => {
          MediaSyncStatus.failedRetryable.name,
          MediaSyncStatus.failedPermanent.name,
          MediaSyncStatus.missingLocal.name,
          MediaSyncStatus.remoteMissing.name,
        }.contains(v),
      )
      .length;
  int get pendingCount => pendingDiagnostics + pendingPhotos;
  bool get allSynchronized =>
      pendingDiagnostics == 0 && pendingPhotos == 0 && syncErrors == 0;

  Future<void> initialize() async {
    connectivityMonitor?.addListener(_onConnectivityChanged);
    _clearAccessScope();
    _replaceHydrantsFromCache();
    activeChecklist = checklistRepository.cached();
    final localSession = await sessionRepository.storage.read();
    if (localSession != null) {
      _session = localSession;
      sessionOffline = true;
      _applySession(localSession);
    }
    initialized = true;
    notifyListeners();
    unawaited(_completePendingLogout());
    unawaited(_initializeRemoteServices());
  }

  Future<void> _initializeRemoteServices() async {
    await connectivityMonitor?.start();
    if (_session == null) return;
    try {
      final restored = await sessionRepository.restore();
      if (restored != null) {
        _session = restored;
        sessionOffline = sessionRepository.lastRestoreOffline;
        _applySession(restored);
      }
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.sessionRevoked) {
        _resetActiveSessionState();
        assignmentError = error.message;
      } else {
        sessionOffline = true;
      }
    } on Object {
      sessionOffline = true;
    }
    notifyListeners();
    if (connectivityMonitor?.apiAvailable ?? false) {
      unawaited(synchronizeAssignments());
      unawaited(refreshChecklist());
    }
  }

  void _onConnectivityChanged() {
    online = connectivityMonitor?.apiAvailable ?? online;
    if (online) {
      sessionOffline = false;
      unawaited(_completePendingLogout());
    }
    notifyListeners();
  }

  Future<void> _completePendingLogout() async {
    final completed = await sessionRepository.completePendingLogout();
    if (completed) {
      await preferences.setBool('pending_field_session_end', false);
      if (assignmentError ==
          'Sin conexión. El cierre de sesión quedó pendiente.') {
        assignmentError = null;
      }
      notifyListeners();
    }
  }

  Future<void> recheckConnectivity() async {
    await connectivityMonitor?.check(force: true);
  }

  Future<String?> startFieldSession(FieldRegistration registration) async {
    final stopwatch = Stopwatch()..start();
    try {
      final newSession = await sessionRepository.start(registration);
      _resetActiveSessionState();
      _session = newSession;
      _applySession(newSession);
      sessionOffline = false;
      await trace('login', 'Inicio de sesión de campo');
      notifyListeners();
      unawaited(synchronizeAssignments());
      unawaited(refreshChecklist());
      final monitor = connectivityMonitor;
      if (monitor != null) unawaited(monitor.check());
      debugPrint('[PERF] login_session_ms=${stopwatch.elapsedMilliseconds}');
      return null;
    } on ApiException catch (error) {
      return error.message;
    } on Object {
      return 'Error desconocido.';
    }
  }

  void _applySession(FieldSession session) {
    _remoteProfileStats = null;
    profileStatsLoading = true;
    _user = AppUser(
      id: session.userId,
      fullName: session.name.isEmpty ? 'Inspector de campo' : session.name,
      email: session.email,
      role: 'Inspector',
      brigadeId: session.crewId,
      brigadeName: session.crew,
      deviceId: session.installationId,
    );
    final scope = LocalDataScope(
      environment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      accountId: 'rv-field',
      userId: session.userId,
      brigadeId: session.crewId,
      role: session.role,
    );
    visualInspectionRepository.setAccessScope(scope);
    hydrantRepository.setAccessScope(scope);
    syncQueueRepository.setAccessScope(scope);
    _replaceHydrantsFromCache();
  }

  void _clearAccessScope() {
    visualInspectionRepository.setAccessScope(null);
    hydrantRepository.setAccessScope(null);
    syncQueueRepository.setAccessScope(null);
  }

  Future<bool> logout() async {
    final ended = await sessionRepository.end();
    if (!ended) {
      await preferences.setBool('pending_field_session_end', true);
      assignmentError = 'Sin conexión. El cierre de sesión quedó pendiente.';
    } else {
      await preferences.setBool('pending_field_session_end', false);
    }
    _resetActiveSessionState();
    sessionOffline = false;
    notifyListeners();
    return true;
  }

  void _resetActiveSessionState() {
    sessionRepository.cancelActiveRequests();
    _session = null;
    _remoteProfileStats = null;
    profileStatsLoading = false;
    _clearAccessScope();
    hydrants.clear();
    catalogHydrants.clear();
    assignmentsForReview.clear();
    activeChecklist = null;
    checklistError = null;
    hydrantListFilter = HydrantListFilter.all;
    hydrantFilterRequest = null;
    assignmentSyncing = false;
    lastAssignmentResult = null;
    lastAssignmentCheck = null;
    assignmentCursor = null;
    if (assignmentError !=
        'Sin conexión. El cierre de sesión quedó pendiente.') {
      assignmentError = null;
    }
    syncing = false;
    syncProgress = 0;
  }

  void _replaceHydrantsFromCache() {
    final catalog = hydrantRepository
        .cached(scope: 'all')
        .map((e) => e.toAppModel())
        .toList();
    catalogHydrants
      ..clear()
      ..addAll(catalog);
    final cached = hydrantRepository
        .cached(scope: 'mine')
        .map((e) => e.toAppModel())
        .toList();
    final ids = cached.map((item) => item.id).toSet();
    for (final item in catalog) {
      if (!ids.contains(item.id) &&
          visualInspectionRepository.hasLocalInspection(item.id)) {
        cached.add(item.copyWith(syncStatus: SyncStatus.local));
      }
    }
    hydrants
      ..clear()
      ..addAll(cached);
  }

  Future<void> refreshChecklist() async {
    checklistError = null;
    try {
      activeChecklist = await checklistRepository.refresh();
    } on ApiException catch (error) {
      checklistError = error.message;
      activeChecklist ??= checklistRepository.cached();
    }
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
    final today = DateTime.now();
    bool isToday(DateTime value) {
      final local = value.toLocal();
      return local.year == today.year &&
          local.month == today.month &&
          local.day == today.day;
    }

    final visualHistory = visualInspectionRepository.forHydrant(hydrant.id);
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
      visualSubmittedToday: visualHistory.any(
        (value) =>
            value.status == InspectionStatus.completed &&
            value.completedAt != null &&
            isToday(value.completedAt!),
      ),
      visualPendingToday: visualHistory.any(
        (value) =>
            value.status != InspectionStatus.completed &&
            isToday(value.startedAt),
      ),
    );
  }

  ProfileTodayStats get profileTodayStats {
    final today = DateTime.now();
    bool isToday(DateTime value) {
      final local = value.toLocal();
      return local.year == today.year &&
          local.month == today.month &&
          local.day == today.day;
    }

    final reports = visualInspectionRepository.accessible();
    final submittedIds = {
      for (final report in reports)
        if (report.status == InspectionStatus.completed &&
            report.completedAt != null &&
            isToday(report.completedAt!))
          report.id,
    };
    final pendingIds = {
      for (final report in reports)
        if (report.status != InspectionStatus.completed &&
            isToday(report.startedAt))
          report.id,
    };
    final unsyncedIds = {
      for (final item in syncQueueRepository.all())
        if (item.status != SyncQueueStatus.synced)
          item.inspectionId ?? item.entityId,
      for (final draft in rvDraftRepository.pending())
        if (!draft.isReadOnly) draft.clientInspectionId,
    };
    final local = ProfileTodayStats(
      date: DateTime(today.year, today.month, today.day),
      submitted: submittedIds.length,
      pending: pendingIds.length,
      unsynced: unsyncedIds.length,
    );
    final remote = _remoteProfileStats;
    if (remote == null || remote.date != local.date) return local;
    return ProfileTodayStats(
      date: local.date,
      submitted: remote.submitted,
      pending: remote.pending,
      unsynced: local.unsynced,
    );
  }

  bool _hasUnsynchronizedData(Hydrant hydrant) {
    if (hydrant.syncStatus != SyncStatus.synced) return true;
    for (final item in syncQueueRepository.all()) {
      if (item.hydrantId == hydrant.id &&
          item.status != SyncQueueStatus.synced) {
        return true;
      }
    }
    final photos = Hive.box<String>('inspection_photos_v1');
    for (final raw in photos.values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (photo.capturedByUserId == user.id &&
            photo.hydrantId == hydrant.id &&
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
        if (payload['userId'] == user.id &&
            payload['hydrantId'] == hydrant.id) {
          return true;
        }
      } on Object {
        continue;
      }
    }
    return false;
  }

  Hydrant hydrant(String id) =>
      [...hydrants, ...catalogHydrants].firstWhere((item) => item.id == id);

  void includeLocalHydrant(Hydrant value) {
    if (!hydrants.any((item) => item.id == value.id)) {
      hydrants.add(value.copyWith(syncStatus: SyncStatus.local));
      notifyListeners();
    }
  }

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

  Future<Hydrant> createManualHydrant({
    required String accountNumber,
    required String locality,
    required String municipality,
    required String reason,
    double? latitude,
    double? longitude,
  }) async {
    final localId = const Uuid().v4();
    final environment = const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final cached = await hydrantRepository.createManual(
      localId: localId,
      accountNumber: accountNumber.trim(),
      createdByUserId: user.id,
      accountId: 'rv-field',
      environment: environment,
      reason: reason.trim(),
      locality: locality.trim(),
      municipality: municipality.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    final hydrant = cached.toAppModel();
    includeLocalHydrant(hydrant);
    if (!catalogHydrants.any((item) => item.id == hydrant.id)) {
      catalogHydrants.add(hydrant);
    }
    await enqueueSync(
      entityType: 'manualHydrant',
      entityId: localId,
      hydrantId: localId,
    );
    await trace(
      'manual_hydrant_created',
      'Hidrante manual guardado localmente',
      hydrantId: localId,
      entityType: 'manualHydrant',
      entityId: localId,
      reason: reason.trim(),
    );
    notifyListeners();
    return hydrant;
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
      ownerUserId: user.id,
      accountId: 'rv-field',
      environment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      createdAt: now,
      updatedAt: now,
    );
    await syncQueueRepository.save(item);
    notifyListeners();
  }

  Future<void> synchronize() async {
    if (!online || syncing || allSynchronized) return;
    syncing = true;
    syncProgress = 0;
    notifyListeners();
    await trace('sync_execute', 'Ejecución de sincronización iniciada');
    try {
      for (final item in syncQueueRepository.ready().where(
        (value) => value.entityType == 'manualHydrant',
      )) {
        await hydrantRepository.synchronizeManual(
          item.entityId,
          idempotencyKey: item.idempotencyKey,
        );
        await syncQueueRepository.markSynced(item.id);
      }
      final drafts = rvDraftRepository.pending();
      for (var index = 0; index < drafts.length; index++) {
        await inspectionSyncCoordinator.synchronize(drafts[index]);
        syncProgress = drafts.isEmpty ? 1 : (index + 1) / drafts.length;
        notifyListeners();
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
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
    await trace('assignment_sync_started', 'Consulta de hidrantes iniciada');
    try {
      final before = {for (final item in hydrants) item.id: item};
      List<CachedHydrant>? catalog;
      List<CachedHydrant>? refreshed;
      final partialErrors = <Object>[];
      await Future.wait<void>([
        hydrantRepository.refreshCatalogSnapshot().then<void>(
          (value) => catalog = value,
          onError: (Object error) => partialErrors.add(error),
        ),
        hydrantRepository
            .refresh(scope: 'mine')
            .then<void>(
              (value) => refreshed = value,
              onError: (Object error) => partialErrors.add(error),
            ),
        hydrantRepository.todayStats().then((remoteStats) {
          _remoteProfileStats = ProfileTodayStats(
            date: DateTime(
              remoteStats.date.year,
              remoteStats.date.month,
              remoteStats.date.day,
            ),
            submitted: remoteStats.submitted,
            pending: remoteStats.pending,
            unsynced: 0,
          );
        }, onError: (Object error) => partialErrors.add(error)),
      ]);
      profileStatsLoading = false;
      _replaceHydrantsFromCache();
      final newItems = hydrants
          .where((item) => !before.containsKey(item.id))
          .toList();
      final updated = hydrants
          .where((item) => before.containsKey(item.id))
          .toList();
      final result = AssignmentSyncResult(
        nextCursor: '',
        newAssignments: newItems,
        updatedAssignments: updated,
        removedIds: const [],
        message:
            '${refreshed?.length ?? hydrants.length} hidrantes personales · '
            '${catalog?.length ?? catalogHydrants.length} en catálogo',
      );
      lastAssignmentResult = result;
      online = connectivityMonitor?.apiAvailable ?? partialErrors.length < 3;
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
      if (partialErrors.isNotEmpty) {
        assignmentError =
            'Algunos datos no pudieron actualizarse. Se conservan los datos guardados.';
      }
    } on ApiException catch (error) {
      assignmentError = error.message;
      if (error.kind == ApiErrorKind.serverUnavailable ||
          error.kind == ApiErrorKind.timeout) {
        await recheckConnectivity();
      }
      profileStatsLoading = false;
      lastAssignmentCheck = DateTime.now();
      await trace('assignment_sync_error', assignmentError!);
    }
    assignmentSyncing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    connectivityMonitor?.removeListener(_onConnectivityChanged);
    connectivityMonitor?.dispose();
    super.dispose();
  }

  Future<void> synchronizeNextAssignmentScenario() async {
    await synchronizeAssignments();
  }

  void setAssignmentScenario(AssignmentSyncScenario value) {
    assignmentScenario = value;
    notifyListeners();
  }

  Future<void> checkUpdates({bool manual = true}) async {
    if (!AppConfig.appUpdatesEnabled) return;
    await trace(
      'update_check_started',
      'Comprobación de actualización iniciada',
    );
    updateInfo = await updateService.check(
      installedVersion: packageInfo.version,
      installedBuild: installedBuild,
      manual: manual,
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
