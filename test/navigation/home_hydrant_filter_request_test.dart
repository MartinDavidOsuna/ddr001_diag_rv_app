import 'package:ddr001diag/core/services/app_state.dart';
import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/data/local/functional_repositories.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/hydrant_list_filter.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/auth/data/field_session_repository.dart';
import 'package:ddr001diag/features/hydrants/data/hydrant_repository.dart';
import 'package:ddr001diag/features/checklist/data/checklist_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ddr001diag/features/profile/profile_pages.dart';

import '../helpers/hive_test_environment.dart';
import '../helpers/foundation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HiveTestEnvironment environment;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'demo_session': true});
    environment = HiveTestEnvironment();
    await environment.open();
    final storage = MemorySessionStorage();
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
    );
    final visualRepository = VisualInspectionRepository(
      documents: Hive.box<String>('visual_inspections_v1'),
      index: Hive.box<String>('active_inspection_index_v1'),
    );
    final rvDraftRepository = RvDraftRepository(visualRepository);
    state = AppState(
      preferences: await SharedPreferences.getInstance(),
      traceBox: Hive.box<String>('trace_events'),
      syncBox: Hive.box<String>('sync_queue'),
      mediaBox: Hive.box<String>('media_sync_queue'),
      syncedTraceBox: Hive.box<String>('synced_trace_ids'),
      packageInfo: PackageInfo(
        appName: 'DIAGNOSTICO HIDRANTES',
        packageName: 'ddr001diag',
        version: '0.2.0',
        buildNumber: '3',
      ),
      visualInspectionRepository: visualRepository,
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
          appName: 'DIAGNOSTICO HIDRANTES',
          packageName: 'ddr001diag',
          version: '0.2.0',
          buildNumber: '3',
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
      rvDraftRepository: rvDraftRepository,
      inspectionSyncCoordinator: InspectionSyncCoordinator(
        drafts: rvDraftRepository,
        remote: InspectionRemoteRepository(client),
        photoBox: Hive.box<String>('inspection_photos_v1'),
        mediaQueue: Hive.box<String>('media_sync_queue'),
      ),
    );
  });
  tearDown(() async {
    state.dispose();
    await environment.close();
  });

  test(
    'Inicio publica un request único que conserva filtro hasta consumirse',
    () {
      state.requestHydrantListFilterFromHome(
        HydrantListFilter.synchronizationPending,
      );
      final first = state.hydrantFilterRequest!;
      expect(state.hydrantListFilter, HydrantListFilter.synchronizationPending);
      expect(first.id, startsWith('home-'));

      state.consumeHydrantFilterRequest('otro-id');
      expect(state.hydrantFilterRequest?.id, first.id);
      state.consumeHydrantFilterRequest(first.id);
      expect(state.hydrantFilterRequest, isNull);
      expect(state.hydrantListFilter, HydrantListFilter.synchronizationPending);
    },
  );

  test(
    'una nueva métrica reemplaza la solicitud sin crear estado paralelo',
    () {
      state.requestHydrantListFilterFromHome(HydrantListFilter.completed);
      final firstId = state.hydrantFilterRequest!.id;
      state.requestHydrantListFilterFromHome(HydrantListFilter.inProgress);

      expect(state.hydrantFilterRequest?.id, isNot(firstId));
      expect(state.hydrantFilterRequest?.filter, HydrantListFilter.inProgress);
      state.clearHydrantListFilter();
      expect(state.hydrantListFilter, HydrantListFilter.all);
      expect(state.hydrantFilterRequest, isNull);
    },
  );

  test('conteo y lista consultan la misma proyección central', () {
    for (final filter in const [
      HydrantListFilter.all,
      HydrantListFilter.inProgress,
      HydrantListFilter.completed,
      HydrantListFilter.synchronizationPending,
    ]) {
      expect(
        state.hydrantCountForFilter(filter),
        state.hydrantsForFilter(filter).length,
      );
    }
  });

  test(
    'estado oficial prevalece sobre borrador y traza local obsoletos',
    () async {
      const official = Hydrant(
        id: 'hydrant-1497',
        code: '1497',
        locality: '',
        parcel: '',
        priority: PriorityLevel.medium,
        access: AccessType.vehicle,
        syncStatus: SyncStatus.synced,
        f02a: InspectionSummary(
          type: InspectionType.f02A,
          status: InspectionStatus.completed,
          progress: 1,
        ),
        f02b: InspectionSummary(
          type: InspectionType.f02B,
          status: InspectionStatus.notRequired,
          progress: 0,
        ),
        latitude: 0,
        longitude: 0,
        rvStatus: 'submitted',
        officialInspectionId: 'official-report',
        availableForRv: false,
      );
      state.hydrants.add(official);
      await state.rvDraftRepository.openOrCreate(
        hydrant: official.copyWith(
          f02a: const InspectionSummary(
            type: InspectionType.f02A,
            status: InspectionStatus.pending,
            progress: 0,
          ),
        ),
        user: state.user,
        checklist: DynamicChecklist(
          id: 'rv',
          code: 'rv',
          version: 1,
          title: 'RV',
          etag: 'etag',
          cachedAt: DateTime.now().toUtc(),
          sections: const [],
        ),
      );
      await state.trace('legacy_event', 'Traza previa', hydrantId: official.id);

      expect(state.pendingDiagnostics, 0);
      expect(
        state.hydrantsForFilter(HydrantListFilter.synchronizationPending),
        isEmpty,
      );
      expect(state.hydrantsForFilter(HydrantListFilter.pendingToday), isEmpty);
      expect(state.profileTodayStats.pending, 0);
      expect(state.profileTodayStats.unsynced, 0);
      expect(state.profileTodayStats.submitted, 1);
    },
  );

  testWidgets('Perfil no expone simulación ni actualizaciones', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    expect(find.text('ESTADÍSTICAS ACTUALES'), findsOneWidget);
    expect(find.text('Enviados'), findsOneWidget);
    expect(find.text('Simular conexión'), findsNothing);
    expect(find.text('Revisar actualización'), findsNothing);
    expect(find.textContaining('demostración'), findsNothing);
  });

  testWidgets('Manual operativo contiene flujo RV y no contenido provisional', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ManualPage()),
      ),
    );
    expect(find.byKey(const ValueKey('manual-scroll-view')), findsOneWidget);
    expect(find.textContaining('Inicio de sesión'), findsOneWidget);
    final content = ManualPage.sections
        .map((section) => '${section.$1} ${section.$2}')
        .join(' ');
    expect(content, contains('Válvulas parcelarias'));
    expect(content, contains('Solución de problemas'));
    expect(content.toLowerCase(), isNot(contains('demo')));
    expect(find.textContaining('demo', findRichText: true), findsNothing);
  });
}
