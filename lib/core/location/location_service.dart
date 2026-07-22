import 'package:geolocator/geolocator.dart';

enum LocationFailureReason {
  permissionDenied,
  permissionDeniedForever,
  locationServiceDisabled,
  timeout,
  noPositionAvailable,
  poorAccuracy,
  providerUnavailable,
  platformError,
  unknownTechnicalError,
}

class LocationCaptureException implements Exception {
  const LocationCaptureException(
    this.message, {
    this.permanentlyDenied = false,
    this.reason = LocationFailureReason.unknownTechnicalError,
    this.permissionStatus,
    this.serviceEnabled,
  });
  final String message;
  final bool permanentlyDenied;
  final LocationFailureReason reason;
  final String? permissionStatus;
  final bool? serviceEnabled;
  @override
  String toString() => message;
}

class LocationService {
  Future<Position> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationCaptureException(
        'El servicio de ubicación está desactivado.',
        reason: LocationFailureReason.locationServiceDisabled,
        serviceEnabled: false,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationCaptureException(
        'El permiso de ubicación está denegado permanentemente.',
        permanentlyDenied: true,
        reason: LocationFailureReason.permissionDeniedForever,
        permissionStatus: 'deniedForever',
        serviceEnabled: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationCaptureException(
        'Permiso de ubicación denegado.',
        reason: LocationFailureReason.permissionDenied,
        permissionStatus: 'denied',
        serviceEnabled: true,
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}
