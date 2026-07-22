import 'dart:async';

import 'package:ddr001diag/data/services/cellular_network_diagnostics_controller.dart';
import 'package:ddr001diag/domain/network/cellular_network_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_cellular_probe_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CellularInternetProbeResult success() => CellularInternetProbeResult(
    requestedCellularNetwork: true,
    cellularNetworkAcquired: true,
    transportCellularConfirmed: true,
    internetCapabilityPresent: true,
    validatedCapabilityPresent: true,
    probeAttempted: true,
    responseReceived: true,
    startedAt: DateTime.now().toUtc(),
    completedAt: DateTime.now().toUtc(),
    timeoutReached: false,
    result: CellularInternetProbeOutcome.cellularInternetConfirmed,
    platform: 'android',
    methodVersion: 'test-v1',
    httpStatusCode: 204,
    latencyMs: 100,
  );

  test('progreso nativo y resultado se persisten sin esperar delays', () async {
    final channel = FakeCellularProbeChannel();
    final persisted = <CellularNetworkDiagnostic>[];
    final controller = CellularNetworkDiagnosticsController(
      inspectionId: 'rv-1',
      persist: (value) async => persisted.add(value),
      probeChannel: channel,
    );
    final running = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(channel.startedProbeIds, hasLength(1));
    channel.progress?.call('verifyingCapabilities');
    expect(controller.diagnostic.stage, CellularDiagnosticStage.verifyingCapabilities);
    channel.result.complete(success());
    await running;

    expect(controller.diagnostic.status, CellularDiagnosticStatus.available);
    expect(controller.diagnostic.internetStatus, CellularInternetStatus.available);
    expect(controller.diagnostic.latencyMs, 100);
    expect(persisted.last.status, CellularDiagnosticStatus.available);
    controller.dispose();
  });

  test('cancelar clasifica cancelado y solicita liberar el probe activo', () async {
    final channel = FakeCellularProbeChannel();
    final persisted = <CellularNetworkDiagnostic>[];
    final controller = CellularNetworkDiagnosticsController(
      inspectionId: 'rv-1',
      persist: (value) async => persisted.add(value),
      probeChannel: channel,
    );
    unawaited(controller.start());
    await Future<void>.delayed(Duration.zero);
    final activeId = channel.startedProbeIds.single;

    await controller.cancel();

    expect(channel.cancelledProbeIds, [activeId]);
    expect(controller.diagnostic.status, CellularDiagnosticStatus.cancelled);
    expect(controller.diagnostic.timeoutReached, isFalse);
    controller.dispose();
  });
}
