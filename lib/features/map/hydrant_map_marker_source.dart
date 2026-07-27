import 'package:latlong2/latlong.dart';

import '../../domain/models/app_models.dart';

/// A map-facing projection that keeps marker rendering independent from the
/// hydrant API. A clustering implementation can replace [HydrantMapMarkerSource]
/// without changing repositories or inspection routes.
class HydrantMapItem {
  const HydrantMapItem({required this.hydrant, required this.position});

  final Hydrant hydrant;
  final LatLng position;

  String get id => hydrant.id;
}

abstract interface class HydrantMapMarkerSource {
  const HydrantMapMarkerSource();

  List<HydrantMapItem> itemsFor(Iterable<Hydrant> hydrants);
}

class FlatHydrantMapMarkerSource implements HydrantMapMarkerSource {
  const FlatHydrantMapMarkerSource();

  @override
  List<HydrantMapItem> itemsFor(Iterable<Hydrant> hydrants) => hydrants
      .where(_hasValidCoordinates)
      .map(
        (hydrant) => HydrantMapItem(
          hydrant: hydrant,
          position: LatLng(hydrant.latitude, hydrant.longitude),
        ),
      )
      .toList(growable: false);

  static bool _hasValidCoordinates(Hydrant hydrant) =>
      hydrant.latitude.abs() <= 90 &&
      hydrant.longitude.abs() <= 180 &&
      (hydrant.latitude != 0 || hydrant.longitude != 0);
}

class HydrantMapSelection {
  String? _selectedId;

  String? get selectedId => _selectedId;

  void select(String hydrantId) => _selectedId = hydrantId;

  void clear() => _selectedId = null;

  HydrantMapItem? selectedFrom(Iterable<HydrantMapItem> items) {
    for (final item in items) {
      if (item.id == _selectedId) return item;
    }
    return null;
  }
}

abstract final class HydrantMapCameraPolicy {
  static const double initialZoom = 13;
  static const double selectedHydrantZoom = 17;
  static const double currentLocationZoom = 18;
  static const double minimumZoom = 3;
  static const double maximumZoom = 20;

  static double clampZoom(double zoom) =>
      zoom.clamp(minimumZoom, maximumZoom).toDouble();
}
