import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/features/map/hydrant_map_marker_source.dart';
import 'package:ddr001diag/features/map/hydrant_spatial_index.dart';
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

    test('preserves the exact latitude and longitude of every marker', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'exact', latitude: 28.987654, longitude: -111.123456),
      ]);

      expect(items.single.position.latitude, 28.987654);
      expect(items.single.position.longitude, -111.123456);
    });

    test('keeps every valid cached hydrant for the initial catalog view', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'north', latitude: 29.2, longitude: -110.9),
        _hydrant(id: 'south', latitude: 28.9, longitude: -110.7),
        _hydrant(id: 'missing', latitude: 0, longitude: 0),
      ]);

      expect(items.map((item) => item.id), ['north', 'south']);
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

  group('HydrantSpatialIndex and clustering', () {
    test('returns cached hydrants inside initial 2 km only', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'near', latitude: 22.0005, longitude: -102),
        _hydrant(id: 'far', latitude: 22.1, longitude: -102),
      ]);

      final nearby = HydrantSpatialIndex(
        items,
      ).withinRadius(items.first.position, 2);

      expect(nearby.map((item) => item.id), ['near']);
    });

    test('clusters distant zoom and separates markers at close zoom', () {
      const source = FlatHydrantMapMarkerSource();
      final items = source.itemsFor([
        _hydrant(id: 'one', latitude: 22, longitude: -102),
        _hydrant(id: 'two', latitude: 22.0001, longitude: -102.0001),
      ]);

      expect(
        HydrantMapClusterer.cluster(items, zoom: 10).single.items,
        hasLength(2),
      );
      expect(HydrantMapClusterer.cluster(items, zoom: 17), hasLength(2));
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
