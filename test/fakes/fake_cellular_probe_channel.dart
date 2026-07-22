import 'dart:async';

import 'package:ddr001diag/core/network/cellular_internet_probe_channel.dart';
import 'package:ddr001diag/core/network/cellular_probe_configuration.dart';
import 'package:ddr001diag/domain/network/cellular_network_diagnostic.dart';
import 'package:flutter/services.dart';

class FakeCellularProbeChannel extends CellularInternetProbeChannel {
  FakeCellularProbeChannel()
    : super(
        channel: const MethodChannel('test/fake_cellular_probe'),
        isAndroid: () => false,
        platformName: () => 'test',
      );

  final startedProbeIds = <String>[];
  final cancelledProbeIds = <String>[];
  final Completer<CellularInternetProbeResult> result = Completer();
  CellularProbeProgressCallback? progress;

  @override
  Future<CellularInternetProbeResult> start({
    required String probeId,
    required CellularProbeConfiguration configuration,
    CellularProbeProgressCallback? onProgress,
  }) {
    startedProbeIds.add(probeId);
    progress = onProgress;
    return result.future;
  }

  @override
  Future<void> cancel(String probeId) async {
    cancelledProbeIds.add(probeId);
  }
}
