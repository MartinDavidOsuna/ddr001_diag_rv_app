import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum NetworkAvailabilityState {
  checking,
  noNetwork,
  internetAvailable,
  apiUnavailable,
  apiAvailable,
}

enum NetworkTransport { none, mobile, wireless, ethernet, other }

abstract interface class DeviceConnectivity {
  Future<List<ConnectivityResult>> checkConnectivity();
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

class PluginDeviceConnectivity implements DeviceConnectivity {
  PluginDeviceConnectivity([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;
}

class ConnectivityMonitor extends ChangeNotifier {
  ConnectivityMonitor(
    this._dio, {
    DeviceConnectivity? deviceConnectivity,
    this.minimumCheckInterval = const Duration(seconds: 5),
  }) : _deviceConnectivity = deviceConnectivity ?? PluginDeviceConnectivity();

  final Dio _dio;
  final DeviceConnectivity _deviceConnectivity;
  final Duration minimumCheckInterval;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<NetworkAvailabilityState>? _activeCheck;
  DateTime? _lastCheck;

  NetworkAvailabilityState state = NetworkAvailabilityState.checking;
  NetworkTransport transport = NetworkTransport.none;
  DateTime? checkedAt;
  Duration? apiLatency;
  bool get apiAvailable => state == NetworkAvailabilityState.apiAvailable;

  String get transportLabel => switch (transport) {
    NetworkTransport.none => 'Sin red',
    NetworkTransport.mobile => 'Datos móviles',
    NetworkTransport.wireless => 'Red inalámbrica',
    NetworkTransport.ethernet => 'Ethernet',
    NetworkTransport.other => 'Otra red',
  };
  String get serviceLabel => switch (state) {
    NetworkAvailabilityState.checking => 'Comprobando servidor',
    NetworkAvailabilityState.noNetwork => 'Servicio no disponible',
    NetworkAvailabilityState.internetAvailable => 'Comprobando servidor',
    NetworkAvailabilityState.apiUnavailable => 'Servidor no disponible',
    NetworkAvailabilityState.apiAvailable => 'Servidor disponible',
  };
  String get label => '$transportLabel · $serviceLabel';

  Future<void> start() async {
    _subscription ??= _deviceConnectivity.onConnectivityChanged.listen(
      (_) => unawaited(check()),
    );
    await check(force: true);
  }

  Future<NetworkAvailabilityState> check({bool force = false}) {
    final active = _activeCheck;
    if (active != null) return active;
    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < minimumCheckInterval) {
      return SynchronousFuture(state);
    }
    final future = _performCheck();
    _activeCheck = future;
    return future.whenComplete(() => _activeCheck = null);
  }

  Future<NetworkAvailabilityState> _performCheck() async {
    _lastCheck = DateTime.now();
    final interfaces = await _deviceConnectivity.checkConnectivity();
    transport = _transport(interfaces);
    if (interfaces.isEmpty ||
        interfaces.every((value) => value == ConnectivityResult.none)) {
      return _set(NetworkAvailabilityState.noNetwork);
    }
    _set(NetworkAvailabilityState.internetAvailable);
    final stopwatch = Stopwatch()..start();
    try {
      await _dio.get<Map<String, dynamic>>(
        '/health/live',
        options: Options(
          extra: const {
            'skipAuth': true,
            'connectivityProbe': true,
            'maxRetries': 0,
          },
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      stopwatch.stop();
      apiLatency = stopwatch.elapsed;
      return _set(NetworkAvailabilityState.apiAvailable);
    } on DioException {
      stopwatch.stop();
      apiLatency = stopwatch.elapsed;
      return _set(NetworkAvailabilityState.apiUnavailable);
    }
  }

  NetworkTransport _transport(List<ConnectivityResult> values) {
    if (values.isEmpty ||
        values.every((value) => value == ConnectivityResult.none)) {
      return NetworkTransport.none;
    }
    if (values.contains(ConnectivityResult.wifi)) {
      return NetworkTransport.wireless;
    }
    if (values.contains(ConnectivityResult.mobile)) {
      return NetworkTransport.mobile;
    }
    if (values.contains(ConnectivityResult.ethernet)) {
      return NetworkTransport.ethernet;
    }
    return NetworkTransport.other;
  }

  NetworkAvailabilityState _set(NetworkAvailabilityState value) {
    state = value;
    checkedAt = DateTime.now();
    notifyListeners();
    return value;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
