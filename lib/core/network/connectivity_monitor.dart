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
  DateTime? checkedAt;
  Duration? apiLatency;
  bool get apiAvailable => state == NetworkAvailabilityState.apiAvailable;

  String get label => switch (state) {
    NetworkAvailabilityState.checking => 'Comprobando conexión',
    NetworkAvailabilityState.noNetwork => 'Sin conexión',
    NetworkAvailabilityState.internetAvailable => 'Internet disponible',
    NetworkAvailabilityState.apiUnavailable => 'Servidor no disponible',
    NetworkAvailabilityState.apiAvailable => 'API disponible',
  };

  Future<void> start() async {
    _subscription ??= _deviceConnectivity.onConnectivityChanged.listen(
      (_) => unawaited(check(force: true)),
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
            'maxRetries': 1,
          },
          receiveTimeout: const Duration(seconds: 8),
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
