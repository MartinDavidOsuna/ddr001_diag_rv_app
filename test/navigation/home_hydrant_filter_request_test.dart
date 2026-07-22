import 'package:ddr001diag/core/services/app_state.dart';
import 'package:ddr001diag/data/local/functional_repositories.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/hydrant_list_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HiveTestEnvironment environment;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'demo_session': true});
    environment = HiveTestEnvironment();
    await environment.open();
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
      visualInspectionRepository: VisualInspectionRepository(
        documents: Hive.box<String>('visual_inspections_v1'),
        index: Hive.box<String>('active_inspection_index_v1'),
      ),
      functionalEligibilityRepository: FunctionalEligibilityRepository(
        Hive.box<String>('functional_eligibility_v1'),
      ),
      functionalInspectionRepository: FunctionalInspectionRepository(
        documents: Hive.box<String>('functional_inspections_v1'),
        index: Hive.box<String>('active_functional_inspection_index_v1'),
      ),
    );
  });
  tearDown(() async {
    state.dispose();
    await environment.close();
  });

  test('Inicio publica un request único que conserva filtro hasta consumirse', () {
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
  });

  test('una nueva métrica reemplaza la solicitud sin crear estado paralelo', () {
    state.requestHydrantListFilterFromHome(HydrantListFilter.completed);
    final firstId = state.hydrantFilterRequest!.id;
    state.requestHydrantListFilterFromHome(HydrantListFilter.inProgress);

    expect(state.hydrantFilterRequest?.id, isNot(firstId));
    expect(state.hydrantFilterRequest?.filter, HydrantListFilter.inProgress);
    state.clearHydrantListFilter();
    expect(state.hydrantListFilter, HydrantListFilter.all);
    expect(state.hydrantFilterRequest, isNull);
  });

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
}
