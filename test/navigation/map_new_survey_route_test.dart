import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/hydrants/new_survey_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la ruta conserva y codifica el hidrante seleccionado en el mapa', () {
    final route = Uri.parse(newSurveyRouteForHydrant('hydrant id/01'));

    expect(route.path, '/hydrants/new');
    expect(route.queryParameters['hydrantId'], 'hydrant id/01');
    expect(route.toString(), contains('hydrantId=hydrant+id%2F01'));
  });

  test('la navegación sin identificador conserva la ruta base', () {
    expect(newSurveyPath, '/hydrants/new');
    expect(Uri.parse(newSurveyPath).queryParameters, isEmpty);
  });

  test('el hidrante recibido por NewSurveyPage queda primero y visible', () {
    final first = _hydrant('h-1', '1');
    final selected = _hydrant('h-2', '2');

    final ordered = prioritizeSelectedHydrant([first, selected], selected.id);

    expect(ordered.map((item) => item.id), ['h-2', 'h-1']);
    expect(containsSelectedHydrant(ordered, selected.id), isTrue);
  });

  test('un identificador inexistente conserva el orden y no preselecciona', () {
    final hydrants = [_hydrant('h-1', '1'), _hydrant('h-2', '2')];

    final ordered = prioritizeSelectedHydrant(hydrants, 'missing');

    expect(ordered.map((item) => item.id), ['h-1', 'h-2']);
    expect(containsSelectedHydrant(ordered, 'missing'), isFalse);
  });
}

Hydrant _hydrant(String id, String code) => Hydrant(
  id: id,
  code: code,
  locality: 'Localidad',
  parcel: 'Municipio',
  priority: PriorityLevel.medium,
  access: AccessType.both,
  syncStatus: SyncStatus.synced,
  f02a: const InspectionSummary(
    type: InspectionType.f02A,
    status: InspectionStatus.pending,
    progress: 0,
  ),
  f02b: const InspectionSummary(
    type: InspectionType.f02B,
    status: InspectionStatus.pending,
    progress: 0,
  ),
  latitude: 22,
  longitude: -102,
);
