import 'dart:math' as math;

class UtmCoordinate {
  const UtmCoordinate(this.easting, this.northing, this.zone);
  final double easting, northing;
  final String zone;
}

class CoordinateConversionService {
  UtmCoordinate wgs84ToUtm(double latitude, double longitude) {
    final zoneNumber = ((longitude + 180) / 6).floor() + 1;
    final central = (zoneNumber - 1) * 6 - 180 + 3;
    final lat = latitude * math.pi / 180;
    final lonDelta = (longitude - central) * math.pi / 180;
    const a = 6378137.0, eccentricity = 0.00669438, k0 = 0.9996;
    final n = a / math.sqrt(1 - eccentricity * math.sin(lat) * math.sin(lat));
    final t = math.tan(lat) * math.tan(lat);
    final c = eccentricity / (1 - eccentricity) * math.cos(lat) * math.cos(lat);
    final aa = math.cos(lat) * lonDelta;
    final m =
        a *
        ((1 - eccentricity / 4 - 3 * eccentricity * eccentricity / 64) * lat -
            (3 * eccentricity / 8 + 3 * eccentricity * eccentricity / 32) *
                math.sin(2 * lat) +
            15 * eccentricity * eccentricity / 256 * math.sin(4 * lat));
    final easting = k0 * n * (aa + (1 - t + c) * math.pow(aa, 3) / 6) + 500000;
    var northing =
        k0 *
        (m +
            n *
                math.tan(lat) *
                (aa * aa / 2 + (5 - t + 9 * c) * math.pow(aa, 4) / 24));
    if (latitude < 0) northing += 10000000;
    return UtmCoordinate(
      easting.toDouble(),
      northing.toDouble(),
      '$zoneNumber${latitude >= 0 ? 'N' : 'S'}',
    );
  }
}
