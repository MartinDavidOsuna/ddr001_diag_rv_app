import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

abstract interface class MapLocationProvider {
  const MapLocationProvider();

  Future<LatLng> currentLocation();
}

class GeolocatorMapLocationProvider implements MapLocationProvider {
  const GeolocatorMapLocationProvider();

  @override
  Future<LatLng> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const MapLocationException(
        'Activa la ubicación del dispositivo para continuar.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const MapLocationException(
        'Se necesita permiso de ubicación para centrar el mapa.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const MapLocationException(
        'El permiso de ubicación está bloqueado. Habilítalo en Configuración.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }
}

class MapLocationException implements Exception {
  const MapLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
