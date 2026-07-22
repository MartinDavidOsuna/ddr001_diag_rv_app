import 'package:ddr001diag/domain/enums/hydrant_list_filter.dart';
import 'package:ddr001diag/domain/filters/hydrant_query_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HydrantFilterFacts facts({
    bool visual = false,
    bool functional = false,
    bool visualActive = false,
    bool functionalActive = false,
    bool visualDone = false,
    bool functionalDone = false,
    bool unsynchronized = false,
  }) => HydrantFilterFacts(
    visualAvailable: visual,
    functionalAvailable: functional,
    visualInProgress: visualActive,
    functionalInProgress: functionalActive,
    visualCompleted: visualDone,
    functionalCompleted: functionalDone,
    unsynchronized: unsynchronized,
    visualPending: false,
    functionalPending: false,
    functionalRequired: false,
    functionalSuspended: false,
    functionalFailed: false,
    pendingValidation: false,
    hasIncidents: false,
  );

  test('la barra pública conserva exactamente seis filtros y su orden', () {
    expect(HydrantQueryProjection.visibleFilters, [
      HydrantListFilter.all,
      HydrantListFilter.visualReport,
      HydrantListFilter.functionalReport,
      HydrantListFilter.inProgress,
      HydrantListFilter.synchronizationPending,
      HydrantListFilter.completed,
    ]);
  });

  test('En proceso y Finalizado agregan RV o RF con la misma regla', () {
    expect(
      HydrantQueryProjection.matches(
        HydrantListFilter.inProgress,
        facts(functionalActive: true),
      ),
      isTrue,
    );
    expect(
      HydrantQueryProjection.matches(
        HydrantListFilter.completed,
        facts(visualDone: true),
      ),
      isTrue,
    );
    expect(
      HydrantQueryProjection.matches(HydrantListFilter.completed, facts()),
      isFalse,
    );
  });

  test('Sin sincronizar no se deriva de estar en proceso', () {
    final value = facts(functionalActive: true, unsynchronized: false);
    expect(
      HydrantQueryProjection.matches(
        HydrantListFilter.synchronizationPending,
        value,
      ),
      isFalse,
    );
  });
}
