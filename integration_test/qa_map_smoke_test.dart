import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/core/services/app_state.dart';
import 'package:ddr001diag/data/local/functional_repositories.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/auth/data/field_session_repository.dart';
import 'package:ddr001diag/features/checklist/data/checklist_repository.dart';
import 'package:ddr001diag/features/hydrants/data/hydrant_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/map/map_location_provider.dart';
import 'package:ddr001diag/features/map/map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    as vector_tiles;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/helpers/foundation_fakes.dart';
import '../test/helpers/hive_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late HiveTestEnvironment environment;
  late AppState state;
  late GoRouter router;
  var stateReady = false;
  var routerReady = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    environment = HiveTestEnvironment();
    await environment.open();
    state = await _createState();
    stateReady = true;
    state
      ..online = false
      ..catalogHydrants.addAll([
        _hydrant(
          id: 'qa-map-pending',
          code: 'QA-MAP-001',
          latitude: 22.0000,
          longitude: -102.3000,
        ),
        _hydrant(
          id: 'qa-map-reviewed',
          code: 'QA-MAP-002',
          latitude: 22.0060,
          longitude: -102.2940,
          completed: true,
        ),
      ]);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const MapPage(locationProvider: _FixedLocationProvider()),
        ),
        GoRoute(
          path: '/hydrants/new',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'QA abrió ${state.uri.queryParameters['hydrantId']}',
                key: const ValueKey('qa-map-opened-hydrant'),
              ),
            ),
          ),
        ),
      ],
    );
    routerReady = true;
  });

  tearDown(() async {
    if (routerReady) router.dispose();
    if (stateReady) state.dispose();
    await environment.close();
  });

  testWidgets('OpenFreeMap abre y conserva la experiencia local completa', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(vector_tiles.VectorTileLayer).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(vector_tiles.VectorTileLayer), findsOneWidget);
    expect(find.textContaining('API KEY REQUIRED'), findsNothing);
    expect(find.textContaining('carto.com'), findsNothing);
    expect(find.bySemanticsLabel('Cuenta QA-MAP-001, RV pendiente'), findsOne);
    expect(find.bySemanticsLabel('Cuenta QA-MAP-002, RV terminada'), findsOne);

    await tester.tap(find.byKey(const ValueKey('map-filter-reviewed')));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Cuenta QA-MAP-001, RV pendiente'),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Cuenta QA-MAP-002, RV terminada'), findsOne);

    await tester.tap(find.byKey(const ValueKey('map-filter-all')));
    await tester.tap(find.byKey(const ValueKey('map-zoom-in')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('map-zoom-out')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(find.byType(FlutterMap), const Offset(80, 20));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('map-search-region')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-my-location')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('Mi ubicación'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('map-show-all')));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.bySemanticsLabel('Cuenta QA-MAP-001, RV pendiente'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cuenta QA-MAP-001'), findsOneWidget);
    expect(find.text('Iniciar nueva revisión'), findsOneWidget);

    await tester.tap(find.text('Iniciar nueva revisión'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('qa-map-opened-hydrant')), findsOneWidget);
    expect(find.text('QA abrió qa-map-pending'), findsOneWidget);

    router.pop();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FlutterMap), findsOneWidget);
    if (const bool.fromEnvironment('QA_CAPTURE_EVIDENCE')) {
      await Future<void>.delayed(const Duration(seconds: 20));
    }
    semantics.dispose();
  });
}

Future<AppState> _createState() async {
  final storage = MemorySessionStorage();
  final client = ApiClient(
    config: AppConfig.fromEnvironment(
      environmentOverride: 'qa',
      apiBaseUrlOverride: 'http://127.0.0.1:18080/api/v1',
    ),
    sessionStorage: storage,
  );
  final visual = VisualInspectionRepository(
    documents: Hive.box<String>('visual_inspections_v1'),
    index: Hive.box<String>('active_inspection_index_v1'),
  );
  final drafts = RvDraftRepository(visual);
  final coordinator = InspectionSyncCoordinator(
    drafts: drafts,
    remote: InspectionRemoteRepository(client),
    photoBox: Hive.box<String>('inspection_photos_v1'),
    mediaQueue: Hive.box<String>('media_sync_queue'),
  );
  return AppState(
    preferences: await SharedPreferences.getInstance(),
    traceBox: Hive.box<String>('trace_events'),
    syncBox: Hive.box<String>('sync_queue'),
    mediaBox: Hive.box<String>('media_sync_queue'),
    syncedTraceBox: Hive.box<String>('synced_trace_ids'),
    packageInfo: PackageInfo(
      appName: 'DDR001 RV QA',
      packageName: 'com.aquafim.ddr001diag.qa',
      version: '1.0.17-qa',
      buildNumber: '117',
    ),
    visualInspectionRepository: visual,
    functionalEligibilityRepository: FunctionalEligibilityRepository(
      Hive.box<String>('functional_eligibility_v1'),
    ),
    functionalInspectionRepository: FunctionalInspectionRepository(
      documents: Hive.box<String>('functional_inspections_v1'),
      index: Hive.box<String>('active_functional_inspection_index_v1'),
    ),
    sessionRepository: FieldSessionRepository(
      client: client,
      storage: storage,
      packageInfo: PackageInfo(
        appName: 'DDR001 RV QA',
        packageName: 'com.aquafim.ddr001diag.qa',
        version: '1.0.17-qa',
        buildNumber: '117',
      ),
    ),
    hydrantRepository: HydrantRepository(
      client: client,
      box: Hive.box<String>('local_hydrants_v1'),
    ),
    checklistRepository: ChecklistRepository(
      client: client,
      box: Hive.box<String>('rv_checklist_cache_v1'),
    ),
    rvDraftRepository: drafts,
    inspectionSyncCoordinator: coordinator,
  );
}

Hydrant _hydrant({
  required String id,
  required String code,
  required double latitude,
  required double longitude,
  bool completed = false,
}) => Hydrant(
  id: id,
  code: code,
  locality: 'Ubicación sintética',
  parcel: 'Fixture QA',
  priority: PriorityLevel.low,
  access: AccessType.vehicle,
  syncStatus: SyncStatus.synced,
  f02a: InspectionSummary(
    type: InspectionType.f02A,
    status: completed ? InspectionStatus.completed : InspectionStatus.pending,
    progress: completed ? 1 : 0,
  ),
  f02b: const InspectionSummary(
    type: InspectionType.f02B,
    status: InspectionStatus.notRequired,
    progress: 0,
  ),
  latitude: latitude,
  longitude: longitude,
  rvStatus: completed ? 'completed' : 'pending',
  officialInspectionId: completed ? 'qa-official-map' : null,
);

class _FixedLocationProvider implements MapLocationProvider {
  const _FixedLocationProvider();

  @override
  Future<LatLng> currentLocation() async => const LatLng(22.003, -102.297);
}
