import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/location_service.dart';
import '../domain/rv_draft.dart';

abstract interface class RvLocationCapture {
  Future<RvLocationSample> capture();
}

class DeviceRvLocationCapture implements RvLocationCapture {
  DeviceRvLocationCapture([LocationService? service])
    : service = service ?? LocationService();
  final LocationService service;
  @override
  Future<RvLocationSample> capture() async {
    final Position position = await service.capture();
    return RvLocationSample(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      horizontalAccuracy: position.accuracy,
      verticalAccuracy: position.altitudeAccuracy,
      source: 'gps',
      capturedAt: position.timestamp,
    );
  }
}

abstract interface class RvSignalCapture {
  Future<RvSignalSample> capture();
}

class DeviceRvSignalCapture implements RvSignalCapture {
  DeviceRvSignalCapture([Connectivity? connectivity])
    : connectivity = connectivity ?? Connectivity();
  final Connectivity connectivity;
  @override
  Future<RvSignalSample> capture() async {
    final results = await connectivity.checkConnectivity();
    final connected = results.any((e) => e != ConnectivityResult.none);
    final type = results
        .where((e) => e != ConnectivityResult.none)
        .map((e) => e.name)
        .join(',');
    return RvSignalSample(
      generation: connected ? 'UNKNOWN' : 'NONE',
      networkType: type.isEmpty ? null : type,
      connected: connected,
      capturedAt: DateTime.now().toUtc(),
    );
  }
}
