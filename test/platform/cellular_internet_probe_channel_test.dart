import 'package:ddr001diag/core/network/cellular_internet_probe_channel.dart';
import 'package:ddr001diag/core/network/cellular_probe_configuration.dart';
import 'package:ddr001diag/domain/network/cellular_network_diagnostic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('test/cellular_probe');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('envía configuración mínima y convierte respuesta celular tipada', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      received = call;
      return <String, dynamic>{
        'requestedCellularNetwork': true,
        'cellularNetworkAcquired': true,
        'transportCellularConfirmed': true,
        'internetCapabilityPresent': true,
        'validatedCapabilityPresent': true,
        'probeAttempted': true,
        'probeUrlHost': 'probe.example',
        'httpMethod': 'HEAD',
        'httpStatusCode': 204,
        'responseReceived': true,
        'latencyMs': 125,
        'bytesReceived': 0,
        'startedAt': '2026-07-15T18:00:00.000Z',
        'completedAt': '2026-07-15T18:00:00.125Z',
        'timeoutReached': false,
        'result': 'cellularInternetConfirmed',
        'platform': 'android',
        'methodVersion': 'test-v1',
      };
    });
    final adapter = CellularInternetProbeChannel(
      channel: methodChannel,
      isAndroid: () => true,
      platformName: () => 'android',
    );
    const configuration = CellularProbeConfiguration(
      url: 'https://probe.example/connectivity',
      httpMethod: 'HEAD',
      methodVersion: 'test-v1',
    );

    final result = await adapter.start(
      probeId: 'probe-1',
      configuration: configuration,
    );

    expect(received?.method, 'startProbe');
    final arguments = Map<String, dynamic>.from(received?.arguments as Map);
    expect(arguments['url'], configuration.url);
    expect(arguments.keys, isNot(contains('hydrantId')));
    expect(arguments.keys, isNot(contains('userId')));
    expect(result.result, CellularInternetProbeOutcome.cellularInternetConfirmed);
    expect(result.internetCapabilityPresent, isTrue);
    expect(result.validatedCapabilityPresent, isTrue);
    expect(result.latencyMs, 125);
  });

  test('PlatformException queda indeterminado y no se propaga', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(code: 'securityRestriction', message: 'denied');
    });
    final adapter = CellularInternetProbeChannel(
      channel: methodChannel,
      isAndroid: () => true,
      platformName: () => 'android',
    );

    final result = await adapter.start(
      probeId: 'probe-2',
      configuration: CellularProbeConfiguration.demo,
    );

    expect(result.result, CellularInternetProbeOutcome.indeterminate);
    expect(result.errorCode, 'securityRestriction');
  });

  test('plataforma sin aislamiento no invoca el canal ni finge paridad', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      invoked = true;
      return null;
    });
    final adapter = CellularInternetProbeChannel(
      channel: methodChannel,
      isAndroid: () => false,
      platformName: () => 'ios',
    );

    final result = await adapter.start(
      probeId: 'probe-ios',
      configuration: CellularProbeConfiguration.demo,
    );

    expect(invoked, isFalse);
    expect(result.result, CellularInternetProbeOutcome.platformRestricted);
    expect(result.platform, 'ios');
  });

  test('cancel solicita liberar la operación nativa identificada', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      received = call;
      return null;
    });
    final adapter = CellularInternetProbeChannel(
      channel: methodChannel,
      isAndroid: () => true,
    );

    await adapter.cancel('probe-cancel');

    expect(received?.method, 'cancelProbe');
    expect((received?.arguments as Map)['probeId'], 'probe-cancel');
  });
}
