import 'dart:io';

import 'package:ddr001diag/features/home/rv_work_dashboard.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard exposes exactly the six operational groups', () {
    expect(RvWorkGroup.values.map((group) => group.label), [
      'En proceso',
      'Pendientes de sincronizar',
      'Enviados',
      'Validados',
      'Devueltos',
      'Conflictos',
    ]);
  });

  test(
    'dashboard counts distinct hydrants and every tile navigates to its list',
    () {
      final home = File('lib/features/home/home_page.dart').readAsStringSync();
      expect(home, contains('rvDraftRepository.all()'));
      expect(home, contains('RvWorkDashboardProjection.byHydrant'));
      expect(home, contains('/hydrants?workGroup='));
      expect(home, contains('height: 92'));
      final projection = File(
        'lib/features/home/rv_work_dashboard.dart',
      ).readAsStringSync();
      expect(projection, contains('Map<RvWorkGroup, Set<String>>'));
      expect(
        projection,
        isNot(contains('draft.serverInspectionId != null ||')),
      );
    },
  );

  test('map exposes six uniform filters in a three-column grid', () {
    final map = File('lib/features/map/map_page.dart').readAsStringSync();
    expect(map, contains('HydrantMapFilter.values'));
    expect(map, contains('crossAxisCount: 3'));
    expect(map, contains('height: 86'));
    expect(map, contains('mainAxisExtent: 40'));
    for (final label in [
      'Todo',
      'Disponible',
      'Trabajo local',
      'Revisado',
      'Conflicto',
      'Inactivo',
    ]) {
      expect(map, contains("'$label'"));
    }
  });

  test(
    'map renders every hydrant at its exact coordinate without clusters',
    () {
      final map = File('lib/features/map/map_page.dart').readAsStringSync();
      expect(map, contains('for (final item in items)'));
      expect(map, contains('point: item.position'));
      expect(map, isNot(contains('HydrantMapClusterer.cluster(')));
    },
  );

  test(
    'only a creator-owned non-official draft exposes reversible archive',
    () {
      final summary = File(
        'lib/features/inspections/presentation/rv_summary_page.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/features/inspections/data/rv_draft_repository.dart',
      ).readAsStringSync();
      final documents = File(
        'lib/data/local/visual_inspection_repository.dart',
      ).readAsStringSync();
      final hydrants = File(
        'lib/features/hydrants/hydrant_pages.dart',
      ).readAsStringSync();
      expect(summary, contains('canDeleteUnsyncedLocal'));
      expect(summary, contains('Archivar revisión local'));
      expect(hydrants, contains("ValueKey('archive-local-rv')"));
      expect(hydrants, contains('Archivar revisión local'));
      expect(
        documents,
        contains('Sólo el creador puede eliminar este borrador'),
      );
      expect(repository, contains('hasOfficialRemoteState'));
      expect(repository, contains('draft.officialInspectionId != null'));
      expect(repository, contains("'submitted'"));
      expect(repository, contains('archivedByTechnician'));
      expect(repository, contains('reconcileOrphanedInspectionQueue'));
      expect(repository, contains("contains('photo')"));
    },
  );

  test('RV screens do not display or search locality and municipality', () {
    final survey = File(
      'lib/features/hydrants/new_survey_page.dart',
    ).readAsStringSync();
    final hydrants = File(
      'lib/features/hydrants/hydrant_pages.dart',
    ).readAsStringSync();
    expect(survey, isNot(contains('Localidad')));
    expect(survey, isNot(contains('Municipio')));
    expect(survey, isNot(contains('hydrant.locality')));
    expect(survey, isNot(contains('hydrant.parcel')));
    expect(hydrants, isNot(contains('hydrant.locality')));
    expect(hydrants, isNot(contains('hydrant.parcel')));
    expect(hydrants, contains('Buscar número de cuenta'));
  });

  test(
    'completed RV opens the read-only visual report instead of the form',
    () {
      final source = File(
        'lib/features/hydrants/hydrant_pages.dart',
      ).readAsStringSync();
      expect(source, contains("type == 'a'"));
      expect(source, contains("context.push('/visual-report/"));
      expect(source, contains('summary.status == InspectionStatus.completed'));
    },
  );

  test('pending issue carries navigation, instance, focus and severity', () {
    const issue = RvPendingIssue(
      code: 'pilot_connection_missing',
      message: 'Falta respuesta',
      stepIndex: 4,
      componentType: 'parcel_valve',
      instanceId: 'valve-2',
      instanceIndex: 2,
      focusKey: 'parcel:valve-2:pilotConnected',
    );
    expect(issue.stepIndex, 4);
    expect(issue.instanceIndex, 2);
    expect(issue.severity, PendingIssueSeverity.blocking);
  });

  test('mobile RV has no destructive cancel action or endpoint call', () {
    final summary = File(
      'lib/features/inspections/presentation/rv_summary_page.dart',
    ).readAsStringSync();
    final remote = File(
      'lib/features/inspections/data/inspection_remote_repository.dart',
    ).readAsStringSync();
    expect(summary, isNot(contains('Cancelar inspección')));
    expect(remote, isNot(contains('/cancel')));
  });

  test(
    'unified synchronization reuses one active future and refreshes projections',
    () {
      final source = File(
        'lib/core/services/app_state.dart',
      ).readAsStringSync();
      expect(source, contains('final active = _activeSync'));
      expect(source, contains('GlobalSyncStage.projections'));
      expect(source, contains('await synchronizeAssignments()'));
      final evidenceAt = source.indexOf('reconcileInspectionEvidence(draft)');
      final activeReportAt = source.indexOf(
        'inspectionSyncCoordinator.synchronize(',
        evidenceAt + 1,
      );
      expect(evidenceAt, greaterThanOrEqualTo(0));
      expect(activeReportAt, greaterThan(evidenceAt));
      expect(source, isNot(contains('!draftIds.contains')));
    },
  );

  test('submit attempts the current coordinator before deferring work', () {
    final summary = File(
      'lib/features/inspections/presentation/rv_summary_page.dart',
    ).readAsStringSync();
    final appState = File(
      'lib/core/services/app_state.dart',
    ).readAsStringSync();
    final apiClient = File(
      'lib/core/network/api_client.dart',
    ).readAsStringSync();

    expect(summary, contains('inspectionSyncCoordinator.synchronize('));
    expect(summary, contains('submit: true'));
    expect(
      summary,
      isNot(contains('La sincronización comenzó en segundo plano.')),
    );
    expect(summary, contains('result.lastSyncError'));
    expect(appState, contains('submitStatus == RvPartStatus.pending'));
    expect(apiClient, contains('connectTimeout: const Duration(seconds: 30)'));
    expect(apiClient, contains('receiveTimeout: const Duration(seconds: 30)'));
    expect(apiClient, contains('sendTimeout: const Duration(seconds: 30)'));
  });

  test('map filter labels document all six visible selections', () {
    final source = File('lib/features/map/map_page.dart').readAsStringSync();
    for (final label in [
      'Todo',
      'Disponible',
      'Trabajo local',
      'Revisado',
      'Conflicto',
      'Inactivo',
    ]) {
      expect(source, contains(label));
    }
  });
}
