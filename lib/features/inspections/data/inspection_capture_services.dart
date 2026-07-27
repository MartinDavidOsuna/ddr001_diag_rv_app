import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
  DeviceRvSignalCapture({
    Connectivity? connectivity,
    MethodChannel? channel,
    RvPhonePermission? permission,
  }) : connectivity = connectivity ?? Connectivity(),
       channel =
           channel ??
           const MethodChannel('com.aquafim.ddr001diag/cellular_telephony'),
       permission = permission ?? DeviceRvPhonePermission();
  final Connectivity connectivity;
  final MethodChannel channel;
  final RvPhonePermission permission;

  @override
  Future<RvSignalSample> capture() async {
    final results = await connectivity.checkConnectivity();
    final connected = results.any((e) => e != ConnectivityResult.none);
    final transports = results
        .where((e) => e != ConnectivityResult.none)
        .map((e) => e.name)
        .join(',');
    final granted = await permission.request();
    if (!granted) {
      return RvSignalSample(
        generation: connected ? 'UNKNOWN' : 'NONE',
        connected: connected,
        capturedAt: DateTime.now().toUtc(),
        transportType: transports.isEmpty ? 'none' : transports,
        availabilityReason: 'permission_denied',
      );
    }
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>('capture');
      return RvSignalSample.fromNative(
        raw ?? const <String, dynamic>{},
        fallbackTransport: transports.isEmpty ? 'none' : transports,
        connected: connected,
      );
    } on PlatformException catch (error) {
      return RvSignalSample(
        generation: connected ? 'UNKNOWN' : 'NONE',
        connected: connected,
        capturedAt: DateTime.now().toUtc(),
        transportType: transports.isEmpty ? 'none' : transports,
        availabilityReason: error.code == 'capture_in_progress'
            ? 'capture_in_progress'
            : 'platform_exception',
      );
    }
  }
}

abstract interface class RvPhonePermission {
  Future<bool> request();
}

class DeviceRvPhonePermission implements RvPhonePermission {
  @override
  Future<bool> request() async => (await Permission.phone.request()).isGranted;
}
