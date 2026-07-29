import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'hydrant_map_marker_source.dart';

class HydrantSpatialIndex {
  HydrantSpatialIndex(Iterable<HydrantMapItem> items) {
    for (final item in items) {
      (_cells[_key(item.position)] ??= []).add(item);
    }
  }

  static const double _cellSize = 0.02;
  final Map<(int, int), List<HydrantMapItem>> _cells = {};

  List<HydrantMapItem> insideBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    final result = <HydrantMapItem>[];
    final minRow = (south / _cellSize).floor();
    final maxRow = (north / _cellSize).floor();
    final minColumn = (west / _cellSize).floor();
    final maxColumn = (east / _cellSize).floor();
    for (var row = minRow; row <= maxRow; row++) {
      for (var column = minColumn; column <= maxColumn; column++) {
        for (final item in _cells[(row, column)] ?? const []) {
          final point = item.position;
          if (point.latitude >= south &&
              point.latitude <= north &&
              point.longitude >= west &&
              point.longitude <= east) {
            result.add(item);
          }
        }
      }
    }
    return result;
  }

  List<HydrantMapItem> withinRadius(LatLng center, double radiusKm) {
    final latitudeDelta = radiusKm / 110.574;
    final longitudeDelta =
        radiusKm /
        (111.32 *
            math.max(math.cos(center.latitude * math.pi / 180).abs(), 0.01));
    return insideBounds(
      south: center.latitude - latitudeDelta,
      west: center.longitude - longitudeDelta,
      north: center.latitude + latitudeDelta,
      east: center.longitude + longitudeDelta,
    ).where((item) => _distanceKm(center, item.position) <= radiusKm).toList();
  }

  static (int, int) _key(LatLng point) => (
    (point.latitude / _cellSize).floor(),
    (point.longitude / _cellSize).floor(),
  );

  static double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0088;
    final latitudeDelta = (b.latitude - a.latitude) * math.pi / 180;
    final longitudeDelta = (b.longitude - a.longitude) * math.pi / 180;
    final latitudeA = a.latitude * math.pi / 180;
    final latitudeB = b.latitude * math.pi / 180;
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(latitudeA) *
            math.cos(latitudeB) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}

class HydrantMapCluster {
  const HydrantMapCluster({required this.items, required this.center});

  final List<HydrantMapItem> items;
  final LatLng center;
  bool get isCluster => items.length > 1;
}

abstract final class HydrantMapClusterer {
  static List<HydrantMapCluster> cluster(
    Iterable<HydrantMapItem> items, {
    required double zoom,
  }) {
    if (zoom >= 16) {
      return [
        for (final item in items)
          HydrantMapCluster(items: [item], center: item.position),
      ];
    }
    final degrees = 360 / (256 * math.pow(2, zoom)) * 52;
    final groups = <(int, int), List<HydrantMapItem>>{};
    for (final item in items) {
      final key = (
        (item.position.latitude / degrees).floor(),
        (item.position.longitude / degrees).floor(),
      );
      (groups[key] ??= []).add(item);
    }
    return groups.values
        .map((group) {
          final latitude =
              group.fold<double>(
                0,
                (sum, item) => sum + item.position.latitude,
              ) /
              group.length;
          final longitude =
              group.fold<double>(
                0,
                (sum, item) => sum + item.position.longitude,
              ) /
              group.length;
          return HydrantMapCluster(
            items: List.unmodifiable(group),
            center: LatLng(latitude, longitude),
          );
        })
        .toList(growable: false);
  }
}
