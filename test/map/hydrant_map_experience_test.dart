import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/features/map/hydrant_map_marker_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HydrantMapMarkerSource', () {
    test('projects only hydrants with valid WGS84 coordinates', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'valid', latitude: 22, longitude: -102),
        _hydrant(id: 'zero', latitude: 0, longitude: 0),
        _hydrant(id: 'invalid-latitude', latitude: 91, longitude: -102),
      ]);

      expect(items.map((item) => item.id), ['valid']);
      expect(items.single.position.latitude, 22);
      expect(items.single.position.longitude, -102);
    });

    test('keeps stable hydrant identities for future clustering', () {
      const source = FlatHydrantMapMarkerSource();
      final hydrant = _hydrant(id: 'hydrant-42', latitude: 22, longitude: -102);

      expect(source.itemsFor([hydrant]).single.id, 'hydrant-42');
    });
  });

  group('HydrantMapSelection', () {
    test('popup selection exists only while its hydrant remains selected', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'one', latitude: 22, longitude: -102),
      ]);
      final selection = HydrantMapSelection()..select('one');

      expect(selection.selectedFrom(items)?.id, 'one');
      selection.clear();
      expect(selection.selectedFrom(items), isNull);
    });

    test(
      'drops the visible popup if the selected hydrant is no longer listed',
      () {
        final selection = HydrantMapSelection()..select('missing');

        expect(selection.selectedFrom(const []), isNull);
      },
    );
  });

  group('HydrantMapCameraPolicy', () {
    test('uses the specified initial, selection and location zoom levels', () {
      expect(HydrantMapCameraPolicy.initialZoom, 13);
      expect(HydrantMapCameraPolicy.selectedHydrantZoom, 17);
      expect(HydrantMapCameraPolicy.currentLocationZoom, 18);
    });

    test('zoom buttons stay inside supported limits', () {
      expect(HydrantMapCameraPolicy.clampZoom(-10), 3);
      expect(HydrantMapCameraPolicy.clampZoom(30), 20);
    });
  });
}

Hydrant _hydrant({
  required String id,
  required double latitude,
  required double longitude,
}) => Hydrant(
  id: id,
  code: id,
  locality: 'Localidad',
  parcel: 'Parcela',
  priority: PriorityLevel.medium,
  access: AccessType.both,
  syncStatus: SyncStatus.synced,
  latitude: latitude,
  longitude: longitude,
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
);
