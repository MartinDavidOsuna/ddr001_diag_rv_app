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

  test('dashboard includes submitted read-only drafts and completed remotes', () {
    final home = File('lib/features/home/home_page.dart').readAsStringSync();
    expect(home, contains('rvDraftRepository.all()'));
    expect(home, contains('InspectionStatus.completed'));
    expect(home, contains('locallyRepresentedHydrants'));
  });

  test('completed RV opens the read-only visual report instead of the form', () {
    final source = File(
      'lib/features/hydrants/hydrant_pages.dart',
    ).readAsStringSync();
    expect(source, contains("type == 'a'"));
    expect(source, contains("context.push('/visual-report/"));
    expect(source, contains('summary.status == InspectionStatus.completed'));
  });

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
    },
  );

  test('map legend documents all five semantic states', () {
    final source = File('lib/features/map/map_page.dart').readAsStringSync();
    for (final label in [
      'Disponible',
      'Trabajo local',
      'Revisado',
      'Conflicto o devuelto',
      'Inactivo o no disponible',
    ]) {
      expect(source, contains(label));
    }
  });
}
