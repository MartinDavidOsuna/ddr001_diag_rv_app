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
import '../../domain/inspections/visual_inspection.dart';
import '../../domain/sync/sync_queue_item.dart';
import '../../features/auth/data/field_session_models.dart';
import '../../features/auth/data/field_session_repository.dart';
import '../../features/hydrants/data/hydrant_repository.dart';
import '../../features/hydrants/data/hydrant_api_models.dart';
import '../../features/home/rv_work_dashboard.dart';
import '../../features/checklist/data/checklist_models.dart';
import '../../features/checklist/data/checklist_repository.dart';
import '../../features/inspections/data/inspection_sync_coordinator.dart';
import '../../features/inspections/data/rv_draft_repository.dart';
import '../../features/inspections/domain/rv_draft.dart';
import '../../features/inspections/domain/rv_sync_state.dart';
import '../../features/catalogs/dynamic_catalog_repository.dart';
import '../../features/visual_reports/data/visual_report_repository.dart';
import '../../features/diagnostics/rv_diagnostic_export_service.dart';
import '../config/app_config.dart';
import '../network/api_exception.dart';
import '../network/connectivity_monitor.dart';
import '../security/local_data_scope.dart';
import 'update_service.dart';

enum GlobalSyncStage {
  idle,
  waitingConnection,
  preparing,
  catalogs,
  reports,
  projections,
  completed,
  completedWithWarnings,
  paused,
}

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
    this.diagnosticExportService,
    this.visualReportRepository,
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
  final RvDiagnosticExportService? diagnosticExportService;
  final VisualReportRepository? visualReportRepository;
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
  GlobalSyncStage syncStage = GlobalSyncStage.idle;
  int syncTotal = 0, syncCompleted = 0, syncWarnings = 0, syncConflicts = 0;
  String? syncingReport;
  String? syncPauseMessage;
  Future<void>? _activeSync;
  UpdateInfo? updateInfo;
  AssignmentSyncScenario assignmentScenario = AssignmentSyncScenario.noChanges;
  AssignmentSyncResult? lastAssignmentResult;
  DateTime? lastAssignmentCheck;
  String? assignmentError, assignmentCursor;
  String? pendingSessionTakeoverToken;
  HydrantListFilter hydrantListFilter = HydrantListFilter.all;
  HydrantFilterRequest? hydrantFilterRequest;
  int _hydrantFilterRequestSequence = 0;
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
  int get pendingDiagnostics {
    final pendingIds = <String>{};
    for (final item in syncQueueRepository.all()) {
      if (item.status == SyncQueueStatus.synced) continue;
      final draft = item.inspectionId == null
          ? null
          : rvDraftRepository.find(item.inspectionId!);
      if (draft != null && _isSupersededByOfficialState(draft)) continue;
      pendingIds.add(item.inspectionId ?? item.id);
    }
    pendingIds.addAll(
      _pendingDraftsForSync().map((draft) => draft.clientInspectionId),
    );
    return pendingIds.length + syncQueueRepository.unreadableCount;
  }

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

  Set<String> get pendingPhotoIds {
    if (!authenticated) return const {};
    final pendingInspectionIds = _pendingDraftsForSync()
        .map((draft) => draft.clientInspectionId)
        .toSet();
    final ids = <String>{};
    final photos = Hive.box<String>('inspection_photos_v1');
    for (final raw in photos.values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (photo.capturedByUserId == user.id &&
            pendingInspectionIds.contains(photo.inspectionId) &&
            mediaBox.get(photo.id) != MediaSyncStatus.verified.name) {
          ids.add(photo.id);
        }
      } on Object {
        continue;
      }
    }
    return ids;
  }

  int get pendingPhotos => pendingPhotoIds
      .where((id) => mediaBox.get(id) != MediaSyncStatus.verified.name)
      .length;
  int get verifiedPhotos => accessiblePhotoIds
      .where((id) => mediaBox.get(id) == MediaSyncStatus.verified.name)
      .length;

  String? photoSyncError(String id) {
    final raw = Hive.box<String>('inspection_photos_v1').get(id);
    if (raw == null) return null;
    try {
      return InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      ).lastError;
    } on Object {
      return 'El registro local de esta evidencia no se pudo interpretar.';
    }
  }

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

  int get syncErrors => pendingPhotoIds
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

  Future<RvDiagnosticExportResult> exportSyncDiagnostic({
    DiagnosticProgress? onProgress,
  }) {
    final exporter = diagnosticExportService;
    if (exporter == null) {
      throw StateError('El exportador de diagnóstico no está disponible.');
    }
    final groups = RvWorkDashboardProjection.byHydrant(
      drafts: rvDraftRepository.all(),
      hydrants: [...hydrants, ...catalogHydrants],
    );
    return exporter.export(
      onProgress: onProgress,
      hydrants: [...hydrants, ...catalogHydrants],
      screenSummary: {
        'home': {
          'inProgress': groups[RvWorkGroup.inProgress]!.length,
          'pendingSync': groups[RvWorkGroup.pendingSync]!.length,
          'sent': groups[RvWorkGroup.submitted]!.length,
          'validated': groups[RvWorkGroup.validated]!.length,
          'returned': groups[RvWorkGroup.returned]!.length,
          'conflicts': groups[RvWorkGroup.conflicts]!.length,
        },
        'syncPage': {
          'pendingDiagnostics': pendingDiagnostics,
          'pendingPhotos': pendingPhotos,
          'verifiedPhotos': verifiedPhotos,
          'errorCount': syncErrors,
        },
      },
    );
  }

  Future<void> deleteUnsyncedLocalDraft(String clientInspectionId) async {
    final draft = rvDraftRepository.find(clientInspectionId);
    if (draft == null) {
      throw StateError('No se encontró la revisión local.');
    }
    if (!canDeleteUnsyncedLocalDraft(clientInspectionId)) {
      throw StateError(
        'Esta revisión ya fue enviada y no puede eliminarse localmente.',
      );
    }
    await rvDraftRepository.deleteUnsyncedLocal(
      clientInspectionId: clientInspectionId,
      creatorId: user.id,
    );
    if (visualInspectionRepository.forHydrant(draft.hydrantId).isEmpty) {
      await hydrantRepository.deleteUnsyncedManualLocal(
        hydrantId: draft.hydrantId,
        creatorId: user.id,
      );
    }
    _replaceHydrantsFromCache();
    notifyListeners();
  }

  bool canDeleteUnsyncedLocalDraft(String clientInspectionId) {
    final draft = rvDraftRepository.find(clientInspectionId);
    if (draft == null) return false;
    return rvDraftRepository.canDeleteUnsyncedLocal(
      clientInspectionId: clientInspectionId,
      creatorId: user.id,
    );
  }

  static bool _hasOfficialRvState(Hydrant hydrant) =>
      hydrant.officialInspectionId != null ||
      const {
        'submitted',
        'completed',
        'validated',
      }.contains(hydrant.rvStatus) ||
      const {
        InspectionStatus.completed,
        InspectionStatus.validated,
      }.contains(hydrant.f02a.status);

  Future<void> initialize({bool startRemoteServices = true}) async {
    connectivityMonitor?.addListener(_onConnectivityChanged);
    _clearAccessScope();
    _replaceHydrantsFromCache();
    activeChecklist = checklistRepository.cached();
    final localSession = await sessionRepository.storage.read();
    if (localSession != null) {
      _session = localSession;
      sessionOffline = true;
      _applySession(localSession);
      await rvDraftRepository.reconcileOrphanedInspectionQueue(
        creatorId: localSession.userId,
      );
      await _reconcileLegacyDeletedManualHydrants(localSession.userId);
    }
    initialized = true;
    notifyListeners();
    if (startRemoteServices) {
      unawaited(_completePendingLogout());
      unawaited(_initializeRemoteServices());
    }
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
      if (error.kind == ApiErrorKind.sessionRevoked ||
          error.kind == ApiErrorKind.authenticationRequired ||
          error.kind == ApiErrorKind.sessionExpired) {
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
      if (pendingCount > 0) unawaited(synchronize());
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
      pendingSessionTakeoverToken = null;
      final newSession = await sessionRepository.start(registration);
      _resetActiveSessionState();
      _session = newSession;
      _applySession(newSession);
      sessionOffline = false;
      await trace('login', 'Inicio de sesión de campo');
      notifyListeners();
      unawaited(synchronizeAssignments());
      unawaited(refreshChecklist());
      unawaited(synchronize());
      final monitor = connectivityMonitor;
      if (monitor != null) unawaited(monitor.check());
      debugPrint('[PERF] login_session_ms=${stopwatch.elapsedMilliseconds}');
      return null;
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.sessionAlreadyActive &&
          error.takeoverToken?.isNotEmpty == true) {
        pendingSessionTakeoverToken = error.takeoverToken;
        return 'Tu usuario ya está activo en otro dispositivo. ¿Deseas cerrar esa sesión? Presiona aquí';
      }
      return error.message;
    } on Object {
      return 'Error desconocido.';
    }
  }

  Future<String?> revokeExistingFieldSession() async {
    final token = pendingSessionTakeoverToken;
    if (token == null || token.isEmpty) {
      return 'La autorización para cerrar la sesión ya no está disponible. Intenta iniciar sesión nuevamente.';
    }
    try {
      await sessionRepository.revokeExisting(token);
      pendingSessionTakeoverToken = null;
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.kind == ApiErrorKind.timeout
          ? 'El servidor tardó demasiado en responder. La sesión anterior no se modificó.'
          : error.message;
    } on Object {
      return 'No fue posible cerrar la sesión del otro dispositivo.';
    }
  }

  void _applySession(FieldSession session) {
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
    dynamicCatalogRepository?.setOwner(session.userId);
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
    final latestLocalByHydrant = <String, VisualInspection>{};
    for (final report in visualInspectionRepository.accessible()) {
      final current = latestLocalByHydrant[report.hydrantId];
      if (current == null || report.updatedAt.isAfter(current.updatedAt)) {
        latestLocalByHydrant[report.hydrantId] = report;
      }
    }
    Hydrant project(Hydrant item) {
      final report = latestLocalByHydrant[item.id];
      if (report == null || report.status != InspectionStatus.completed) {
        return item;
      }
      final draft = rvDraftRepository.fromInspection(report);
      final validated = draft?.remoteStatus == 'validated';
      return item.copyWith(
        syncStatus: validated ? SyncStatus.validated : SyncStatus.synced,
        f02a: InspectionSummary(
          type: item.f02a.type,
          status: validated
              ? InspectionStatus.validated
              : InspectionStatus.completed,
          progress: 1,
        ),
        lastStatusChangedAt:
            draft?.lastStatusChangedAt ??
            report.completedAt ??
            report.updatedAt,
        photoCount: draft?.photoCount ?? report.photoIds.length,
      );
    }

    final catalog = hydrantRepository
        .cached(scope: 'all')
        .map((e) => project(e.toAppModel()))
        .toList();
    catalogHydrants
      ..clear()
      ..addAll(catalog);
    final assigned = hydrantRepository
        .cached(scope: 'mine')
        .map((e) => project(e.toAppModel()))
        .toList();
    final cached = RvWorkDashboardProjection.personalWorkHydrants(
      assigned: assigned,
      catalog: catalog,
      drafts: rvDraftRepository.all(),
    );
    hydrants
      ..clear()
      ..addAll(cached);
  }

  void reconcileLocalWorkProjection() {
    _replaceHydrantsFromCache();
    notifyListeners();
  }

  Future<void> _reconcileLegacyDeletedManualHydrants(String creatorId) async {
    final queuedManuals = syncQueueRepository
        .all()
        .where(
          (item) =>
              item.entityType == 'manualHydrant' &&
              item.ownerUserId == creatorId &&
              item.status != SyncQueueStatus.synced,
        )
        .toList(growable: false);
    for (final item in queuedManuals) {
      final hydrantId = item.hydrantId ?? item.entityId;
      if (hydrantId.isEmpty ||
          visualInspectionRepository.forHydrant(hydrantId).isNotEmpty) {
        continue;
      }
      final removed = await hydrantRepository.deleteUnsyncedManualLocal(
        hydrantId: hydrantId,
        creatorId: creatorId,
      );
      if (removed) await syncQueueRepository.delete(item.id);
    }
    _replaceHydrantsFromCache();
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
    final activeDraft = rvDraftRepository.activeFor(hydrant.id);
    // The official state describes one historical review. Any distinct active
    // draft is additional work for the same hydrant and must stay visible.
    final officialWithoutActiveReview =
        _hasOfficialRvState(hydrant) && activeDraft == null;
    final visualInProgress =
        !officialWithoutActiveReview &&
        (hydrant.f02a.status == InspectionStatus.inProgress ||
            activeDraft != null);
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
      unsynchronized:
          !officialWithoutActiveReview && _hasUnsynchronizedData(hydrant),
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
      visualPendingToday:
          !officialWithoutActiveReview &&
          visualHistory.any(
            (value) =>
                value.status != InspectionStatus.completed &&
                isToday(value.startedAt),
          ),
    );
  }

  ProfileTodayStats get profileTodayStats {
    final today = DateTime.now();
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: rvDraftRepository.all(),
      hydrants: hydrants,
    );
    return ProfileTodayStats(
      date: DateTime(today.year, today.month, today.day),
      submitted: grouped[RvWorkGroup.submitted]!.length,
      pending: grouped[RvWorkGroup.inProgress]!.length,
      unsynced: grouped[RvWorkGroup.pendingSync]!.length,
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
    return false;
  }

  bool _isSupersededByOfficialState(RvDraft draft) {
    // An official inspection belongs to one review, not to the hydrant as a
    // whole. A different local clientInspectionId is an additional review and
    // must remain eligible for synchronization. Explicit local recovery marks
    // true duplicates with supersededBy; RvDraftRepository.pending() already
    // excludes those records.
    return false;
  }

  List<RvDraft> _pendingDraftsForSync() {
    final all = rvDraftRepository.all();
    final submittedHydrants = all
        .where((draft) => draft.localStatus == RvLocalStatus.submitted)
        .map((draft) => draft.hydrantId)
        .toSet();
    return all
        .where(
          (draft) =>
              (draft.supersededBy == null) &&
              !RvWorkDashboardProjection.isEmptyLegacySyncShell(draft) &&
              !(draft.remoteStatus == 'conflict' &&
                  submittedHydrants.contains(draft.hydrantId)) &&
              (!draft.isReadOnly ||
                  (draft.localStatus == RvLocalStatus.conflict &&
                      draft.serverInspectionId != null)) &&
              !_isSupersededByOfficialState(draft) &&
              (draft.localStatus != RvLocalStatus.conflict ||
                  draft.serverInspectionId != null) &&
              draft.localStatus != RvLocalStatus.versionConflict &&
              draft.localStatus != RvLocalStatus.cancelled &&
              (draft.localStatus != RvLocalStatus.submitted ||
                  draft.hasPendingChanges),
        )
        .toList(growable: false);
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

  Future<void> synchronize() {
    final active = _activeSync;
    if (active != null) return active;
    final run = _runUnifiedSynchronization();
    _activeSync = run;
    return run.whenComplete(() => _activeSync = null);
  }

  Future<void> _runUnifiedSynchronization() async {
    if (!online) {
      syncStage = GlobalSyncStage.waitingConnection;
      notifyListeners();
      return;
    }
    if (allSynchronized) {
      syncStage = GlobalSyncStage.completed;
      notifyListeners();
      return;
    }
    syncing = true;
    syncStage = GlobalSyncStage.preparing;
    syncProgress = 0;
    syncCompleted = 0;
    syncWarnings = 0;
    syncConflicts = 0;
    syncPauseMessage = null;
    notifyListeners();
    await trace('sync_execute', 'Ejecución de sincronización iniciada');
    try {
      await _completePendingLogout();
      syncStage = GlobalSyncStage.catalogs;
      try {
        await dynamicCatalogRepository?.synchronizePending();
      } on Object catch (error) {
        syncWarnings++;
        await trace(
          'sync_catalog_warning',
          'La sincronización de catálogos falló; se continuará con los reportes',
          reason: error.toString(),
        );
      }
      final manual = syncQueueRepository
          .ready()
          .where((value) => value.entityType == 'manualHydrant')
          .toList();
      final drafts = _pendingDraftsForSync();
      syncTotal = manual.length + drafts.length;
      for (final item in syncQueueRepository.ready().where(
        (value) => value.entityType == 'manualHydrant',
      )) {
        try {
          await hydrantRepository.synchronizeManual(
            item.entityId,
            idempotencyKey: item.idempotencyKey,
          );
          await syncQueueRepository.markSynced(item.id);
        } on Object {
          syncWarnings++;
        }
        syncCompleted++;
      }
      syncStage = GlobalSyncStage.reports;
      for (var index = 0; index < drafts.length; index++) {
        syncingReport = drafts[index].accountNumber;
        try {
          final result = await inspectionSyncCoordinator.synchronize(
            drafts[index],
            forceRetry: true,
            submit:
                drafts[index].localStatus == RvLocalStatus.submitPending ||
                drafts[index].localStatus == RvLocalStatus.readyToSubmit ||
                drafts[index].submitStatus == RvPartStatus.pending ||
                drafts[index].submitStatus == RvPartStatus.syncing,
          );
          if (result.localStatus == RvLocalStatus.conflict ||
              result.localStatus == RvLocalStatus.versionConflict) {
            syncConflicts++;
          } else if (result.lastSyncError != null) {
            syncWarnings++;
          }
        } on Object catch (error) {
          syncWarnings++;
          await trace(
            'sync_report_isolated_failure',
            'Un reporte falló de forma aislada; se continuará con el siguiente',
            reason: error.toString(),
            metadata: {
              'clientInspectionId': drafts[index].clientInspectionId,
              'accountNumber': drafts[index].accountNumber,
            },
          );
        } finally {
          syncCompleted++;
          syncProgress = syncTotal == 0 ? 1 : syncCompleted / syncTotal;
          notifyListeners();
        }
      }
      syncStage = GlobalSyncStage.projections;
      try {
        await synchronizeAssignments();
      } on Object catch (error) {
        syncWarnings++;
        await trace(
          'sync_projection_warning',
          'La actualización de asignaciones falló después de procesar los reportes',
          reason: error.toString(),
        );
      }
      syncStage = pendingCount > 0 || syncWarnings > 0 || syncConflicts > 0
          ? GlobalSyncStage.completedWithWarnings
          : GlobalSyncStage.completed;
      syncProgress = 1;
    } finally {
      syncing = false;
      syncingReport = null;
      notifyListeners();
    }
  }

  Future<void> retryMedia(String id) async {
    if (mediaBox.get(id) == MediaSyncStatus.verified.name) return;
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
        (hydrantRepository.cached(scope: 'all').isEmpty
                ? hydrantRepository.refreshCatalogSnapshot()
                : hydrantRepository.isCatalogCacheStale()
                ? hydrantRepository.refreshMapChanges()
                : Future.value(hydrantRepository.cached(scope: 'all')))
            .then<void>(
              (value) => catalog = value,
              onError: (Object error) => partialErrors.add(error),
            ),
        hydrantRepository
            .refresh(scope: 'mine')
            .then<void>(
              (value) => refreshed = value,
              onError: (Object error) => partialErrors.add(error),
            ),
        hydrantRepository.todayStats().then<void>(
          (_) {},
          onError: (Object error) => partialErrors.add(error),
        ),
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
    } on Object {
      assignmentError =
          'No fue posible actualizar los hidrantes. Se conservan los datos guardados.';
      profileStatsLoading = false;
      lastAssignmentCheck = DateTime.now();
      await trace('assignment_sync_error', assignmentError!);
    } finally {
      assignmentSyncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshMapCatalog({bool forceSnapshot = false}) async {
    await hydrantRepository.refreshCatalogSnapshot(force: forceSnapshot);
    _replaceHydrantsFromCache();
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
