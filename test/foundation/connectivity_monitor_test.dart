import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ddr001diag/core/network/connectivity_monitor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/foundation_fakes.dart';

class FakeDeviceConnectivity implements DeviceConnectivity {
  FakeDeviceConnectivity(this.current);

  List<ConnectivityResult> current;
  final controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

void main() {
  test(
    'sin interfaz activa informa Sin conexión sin consultar la API',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = FakeHttpAdapter((_) async {
          calls++;
          return jsonResponse('{"status":"ok"}', 200);
        });
      final monitor = ConnectivityMonitor(
        dio,
        deviceConnectivity: FakeDeviceConnectivity([ConnectivityResult.none]),
      );

      expect(
        await monitor.check(force: true),
        NetworkAvailabilityState.noNetwork,
      );
      expect(monitor.transportLabel, 'Sin red');
      expect(monitor.serviceLabel, 'Servicio no disponible');
      expect(calls, 0);
      monitor.dispose();
    },
  );

  test('red activa y health 200 informa API disponible', () async {
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter(
        (_) async => jsonResponse('{"status":"ok"}', 200),
      );
    final monitor = ConnectivityMonitor(
      dio,
      deviceConnectivity: FakeDeviceConnectivity([ConnectivityResult.wifi]),
    );

    expect(
      await monitor.check(force: true),
      NetworkAvailabilityState.apiAvailable,
    );
    expect(monitor.transportLabel, 'Red inalámbrica');
    expect(monitor.serviceLabel, 'Servidor disponible');
    monitor.dispose();
  });

  test('red activa y API caída informa Servidor no disponible', () async {
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
    final monitor = ConnectivityMonitor(
      dio,
      deviceConnectivity: FakeDeviceConnectivity([ConnectivityResult.mobile]),
    );

    expect(
      await monitor.check(force: true),
      NetworkAvailabilityState.apiUnavailable,
    );
    expect(monitor.transportLabel, 'Datos móviles');
    expect(monitor.serviceLabel, 'Servidor no disponible');
    monitor.dispose();
  });

  test('health checks concurrentes se deduplican', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonResponse('{"status":"ok"}', 200);
      });
    final monitor = ConnectivityMonitor(
      dio,
      deviceConnectivity: FakeDeviceConnectivity([ConnectivityResult.wifi]),
    );

    await Future.wait([
      monitor.check(force: true),
      monitor.check(force: true),
      monitor.check(force: true),
    ]);
    expect(calls, 1);
    monitor.dispose();
  });
}
