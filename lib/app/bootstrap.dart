import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'theme/app_theme.dart';
import '../core/widgets/app_brand_logo.dart';
import '../core/services/app_state.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/connectivity_monitor.dart';
import '../data/local/visual_inspection_repository.dart';
import '../data/local/functional_repositories.dart';
import '../data/local/integrity_audit_service.dart';
import '../data/local/operation_journal_repository.dart';
import '../data/local/quarantine_repository.dart';
import '../data/local/recovery_coordinator.dart';
import '../data/local/media_reconciliation_service.dart';
import '../features/auth/data/field_session_repository.dart';
import '../features/auth/data/session_secure_storage.dart';
import '../features/hydrants/data/hydrant_repository.dart';
import '../features/checklist/data/checklist_repository.dart';
import '../features/inspections/data/inspection_remote_repository.dart';
import '../features/inspections/data/inspection_sync_coordinator.dart';
import '../features/inspections/data/rv_draft_repository.dart';
import '../features/catalogs/dynamic_catalog_repository.dart';

typedef BootstrapStatusCallback = void Function(String status);

Future<AppState> bootstrap({BootstrapStatusCallback? onStatus}) async {
  final total = Stopwatch()..start();
  var stage = Stopwatch()..start();
  onStatus?.call('Preparando la aplicación');
  await initializeDateFormatting('es');
  await Hive.initFlutter();
  debugPrint('[PERF] flutter_local_init_ms=${stage.elapsedMilliseconds}');
  stage = Stopwatch()..start();
  onStatus?.call('Inicializando almacenamiento');
  final traceBox = await Hive.openBox<String>('trace_events');
  final syncBox = await Hive.openBox<String>('sync_queue');
  final mediaBox = await Hive.openBox<String>('media_sync_queue');
  final syncedTraceBox = await Hive.openBox<String>('synced_trace_ids');
  final inspectionBox = await Hive.openBox<String>('visual_inspections_v1');
  final inspectionIndexBox = await Hive.openBox<String>(
    'active_inspection_index_v1',
  );
  await Hive.openBox<String>('damage_records_v1');
  await Hive.openBox<String>('inspection_photos_v1');
  await Hive.openBox<String>('hydrant_configurations_v1');
  await Hive.openBox<String>('local_hydrants_v1');
  final hydrantBox = Hive.box<String>('local_hydrants_v1');
  final checklistBox = await Hive.openBox<String>('rv_checklist_cache_v1');
  final dynamicCatalogBox = await Hive.openBox<String>(
    'rv_dynamic_catalogs_v1',
  );
  await Hive.openBox<String>('media_work_queue_v1');
  final functionalEligibilityBox = await Hive.openBox<String>(
    'functional_eligibility_v1',
  );
  final functionalInspectionBox = await Hive.openBox<String>(
    'functional_inspections_v1',
  );
  final functionalInspectionIndexBox = await Hive.openBox<String>(
    'active_functional_inspection_index_v1',
  );
  await Hive.openBox<String>('measurement_series_v1');
  await Hive.openBox<String>('instrument_records_v1');
  await Hive.openBox<String>('functional_valve_tests_v1');
  await Hive.openBox<String>('alarm_tests_v1');
  await Hive.openBox<String>('functional_results_v1');
  await Hive.openBox<String>('functional_test_records_v1');
  final operationJournalBox = await Hive.openBox<String>(
    'operation_journal_v1',
  );
  final quarantineBox = await Hive.openBox<String>('quarantine_documents_v1');
  await Hive.openBox<String>('report_revisions_v1');
  await Hive.openBox<String>('valve_records_v1');
  await Hive.openBox<String>('reducer_runs_v1');
  await Hive.openBox<String>('alarm_attempts_v1');
  await Hive.openBox<String>('instrument_snapshots_v1');
  final integrityReportBox = await Hive.openBox<String>(
    'integrity_audit_reports_v1',
  );
  await Hive.openBox<String>('gallery_ui_state_v1');
  final recovery = await RecoveryCoordinator(
    auditService: const IntegrityAuditService(),
    journal: OperationJournalRepository(operationJournalBox),
    quarantine: QuarantineRepository(quarantineBox),
  ).runLightweight();
  debugPrint('[PERF] local_storage_recovery_ms=${stage.elapsedMilliseconds}');
  await integrityReportBox.put(
    recovery.audit.id,
    jsonEncode(recovery.audit.toJson()),
  );
  await MediaReconciliationService().reconcile();
  onStatus?.call('Recuperando sesión y datos guardados');
  final preferences = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  final config = AppConfig.fromEnvironment();
  final sessionStorage = SessionSecureStorage();
  final apiClient = ApiClient(config: config, sessionStorage: sessionStorage);
  final dynamicCatalogRepository = DynamicCatalogRepository(
    client: apiClient,
    box: dynamicCatalogBox,
  );
  await dynamicCatalogRepository.seed();
  final sessionRepository = FieldSessionRepository(
    client: apiClient,
    storage: sessionStorage,
    packageInfo: packageInfo,
  );
  final visualRepository = VisualInspectionRepository(
    documents: inspectionBox,
    index: inspectionIndexBox,
  );
  final rvDraftRepository = RvDraftRepository(visualRepository);
  final inspectionSyncCoordinator = InspectionSyncCoordinator(
    drafts: rvDraftRepository,
    remote: InspectionRemoteRepository(apiClient),
    photoBox: Hive.box<String>('inspection_photos_v1'),
    mediaQueue: mediaBox,
    catalogs: dynamicCatalogRepository,
  );
  final state = AppState(
    preferences: preferences,
    traceBox: traceBox,
    syncBox: syncBox,
    mediaBox: mediaBox,
    syncedTraceBox: syncedTraceBox,
    packageInfo: packageInfo,
    visualInspectionRepository: visualRepository,
    functionalEligibilityRepository: FunctionalEligibilityRepository(
      functionalEligibilityBox,
    ),
    functionalInspectionRepository: FunctionalInspectionRepository(
      documents: functionalInspectionBox,
      index: functionalInspectionIndexBox,
    ),
    sessionRepository: sessionRepository,
    hydrantRepository: HydrantRepository(client: apiClient, box: hydrantBox),
    checklistRepository: ChecklistRepository(
      client: apiClient,
      box: checklistBox,
    ),
    rvDraftRepository: rvDraftRepository,
    inspectionSyncCoordinator: inspectionSyncCoordinator,
    dynamicCatalogRepository: dynamicCatalogRepository,
    connectivityMonitor: ConnectivityMonitor(apiClient.dio),
  );
  await state.initialize();
  debugPrint('[PERF] bootstrap_total_ms=${total.elapsedMilliseconds}');
  return state;
}

class AppBootstrapShell extends StatefulWidget {
  const AppBootstrapShell({this.bootstrapLoader, super.key});

  final Future<AppState> Function(BootstrapStatusCallback onStatus)?
  bootstrapLoader;

  @override
  State<AppBootstrapShell> createState() => _AppBootstrapShellState();
}

class _AppBootstrapShellState extends State<AppBootstrapShell> {
  AppState? _state;
  Object? _error;
  String _status = 'Iniciando';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      void report(String status) {
        if (mounted) setState(() => _status = status);
      }

      final state =
          await (widget.bootstrapLoader?.call(report) ??
                  bootstrap(onStatus: report))
              .timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _state = state);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != null) return DiagnosticApp(state: state);
    return MaterialApp(
      title: 'DIAGNOSTICO HIDRANTES',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppColors.blue,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppBrandLogo(
                      variant: AppBrandLogoVariant.splash,
                      width: 320,
                      height: 140,
                    ),
                    const SizedBox(height: 32),
                    if (_error == null) ...[
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 18),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No fue posible preparar la aplicación. Revisa la '
                        'configuración e inténtalo nuevamente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _running ? null : _initialize,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
