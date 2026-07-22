import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/cellular_internet_probe_channel.dart';
import '../../core/network/cellular_probe_configuration.dart';
import '../../domain/network/cellular_network_diagnostic.dart';

typedef CellularDiagnosticPersist =
    Future<void> Function(CellularNetworkDiagnostic diagnostic);

class CellularNetworkDiagnosticsController extends ChangeNotifier {
  CellularNetworkDiagnosticsController({
    required String inspectionId,
    required this.persist,
    CellularNetworkDiagnostic? restored,
    CellularInternetProbeChannel? probeChannel,
    this.configuration = CellularProbeConfiguration.demo,
  }) : _probeChannel = probeChannel ?? CellularInternetProbeChannel.instance,
       diagnostic =
           restored ??
           CellularNetworkDiagnostic(
             id: const Uuid().v4(),
             inspectionId: inspectionId,
           );

  final CellularDiagnosticPersist persist;
  final CellularInternetProbeChannel _probeChannel;
  final CellularProbeConfiguration configuration;
  CellularNetworkDiagnostic diagnostic;
  Timer? _countdown;
  String? _activeProbeId;
  bool _disposed = false;
  bool _finishing = false;

  bool get isRunning => diagnostic.isRunning;

  Future<void> start() async {
    if (isRunning || _finishing) return;
    await _stopResources();
    final probeId = const Uuid().v4();
    _activeProbeId = probeId;
    final now = DateTime.now().toUtc();
    diagnostic = CellularNetworkDiagnostic(
      id: probeId,
      inspectionId: diagnostic.inspectionId,
      status: CellularDiagnosticStatus.preparing,
      stage: CellularDiagnosticStage.requestingCellularNetwork,
      startedAt: now,
      attempts: diagnostic.attempts + 1,
      progress: .08,
      method: configuration.methodVersion,
    );
    _emit();
    await persist(diagnostic);
    if (!isRunning || _activeProbeId != probeId) return;

    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRunning || _activeProbeId != probeId) return;
      final elapsed = _elapsedNow();
      final remaining = (60 - elapsed).clamp(0, 60);
      diagnostic = diagnostic.copyWith(
        status: CellularDiagnosticStatus.analyzing,
        elapsedSeconds: elapsed,
        remainingSeconds: remaining,
      );
      _emit();
    });

    final result = await _probeChannel.start(
      probeId: probeId,
      configuration: configuration,
      onProgress: (stage) => _onNativeProgress(probeId, stage),
    );
    if (_disposed || _activeProbeId != probeId || !isRunning) return;
    await _finishFromProbe(probeId, result);
  }

  void _onNativeProgress(String probeId, String stageName) {
    if (_disposed || _activeProbeId != probeId || !isRunning) return;
    final stage = switch (stageName) {
      'requestingCellularNetwork' =>
        CellularDiagnosticStage.requestingCellularNetwork,
      'waitingForAvailability' =>
        CellularDiagnosticStage.waitingForAvailability,
      'verifyingCapabilities' => CellularDiagnosticStage.verifyingCapabilities,
      'testingInternet' => CellularDiagnosticStage.testingInternet,
      'measuringResponse' => CellularDiagnosticStage.measuringResponse,
      'calculatingResult' => CellularDiagnosticStage.calculatingResult,
      _ => null,
    };
    if (stage == null) return;
    final progress = switch (stage) {
      CellularDiagnosticStage.requestingCellularNetwork => .14,
      CellularDiagnosticStage.waitingForAvailability => .28,
      CellularDiagnosticStage.verifyingCapabilities => .48,
      CellularDiagnosticStage.testingInternet => .66,
      CellularDiagnosticStage.measuringResponse => .82,
      CellularDiagnosticStage.calculatingResult => .94,
      _ => diagnostic.progress ?? 0,
    };
    diagnostic = diagnostic.copyWith(
      status: CellularDiagnosticStatus.analyzing,
      stage: stage,
      progress: progress,
    );
    _emit();
  }

  Future<void> _finishFromProbe(
    String probeId,
    CellularInternetProbeResult probe,
  ) async {
    if (_finishing || _activeProbeId != probeId) return;
    _finishing = true;
    _countdown?.cancel();
    _countdown = null;
    final elapsed = _elapsedNow();
    final successfulAttempts =
        diagnostic.successfulAttempts +
        (probe.confirmsCellularInternet ? 1 : 0);
    final evidence = CellularNetworkQualityCalculator.effectiveness(
      probe: probe,
      attempts: diagnostic.attempts,
      successfulAttempts: successfulAttempts,
    );
    final status = switch (probe.result) {
      CellularInternetProbeOutcome.cellularInternetConfirmed ||
      CellularInternetProbeOutcome
          .cellularNetworkAvailableInternetNotConfirmed ||
      CellularInternetProbeOutcome.endpointUnavailable ||
      CellularInternetProbeOutcome.timeout ||
      CellularInternetProbeOutcome.tlsError ||
      CellularInternetProbeOutcome.unexpectedHttpResponse =>
        probe.cellularNetworkAcquired
            ? CellularDiagnosticStatus.available
            : CellularDiagnosticStatus.indeterminate,
      CellularInternetProbeOutcome.cellularNetworkUnavailable =>
        CellularDiagnosticStatus.noCellularNetworksAvailable,
      CellularInternetProbeOutcome.cancelled =>
        CellularDiagnosticStatus.cancelled,
      CellularInternetProbeOutcome.platformRestricted ||
      CellularInternetProbeOutcome.indeterminate =>
        CellularDiagnosticStatus.indeterminate,
    };
    final internetStatus = probe.confirmsCellularInternet
        ? CellularInternetStatus.available
        : status == CellularDiagnosticStatus.cancelled
        ? CellularInternetStatus.cancelled
        : CellularInternetStatus.indeterminate;
    diagnostic = diagnostic.copyWith(
      status: status,
      stage: CellularDiagnosticStage.completed,
      completedAt: DateTime.now().toUtc(),
      elapsedSeconds: elapsed,
      remainingSeconds: (60 - elapsed).clamp(0, 60),
      timeoutReached: probe.timeoutReached,
      interfaceAvailable: probe.cellularNetworkAcquired,
      registeredOnNetwork: probe.cellularNetworkAcquired ? true : null,
      internetStatus: internetStatus,
      latencyMs: probe.latencyMs,
      successfulAttempts: successfulAttempts,
      effectivenessPercentage: evidence.percentage,
      internetProbe: probe,
      effectivenessEvidence: evidence,
      errorCode: probe.errorCode,
      errorMessage: probe.errorMessage,
      platformLimitations: [
        if (probe.result == CellularInternetProbeOutcome.platformRestricted)
          'La plataforma no garantiza el aislamiento de una solicitud a la red celular.',
        'La prueba usa la red celular del teléfono y no certifica el módem del hidrante.',
      ],
      progress: 1,
    );
    _activeProbeId = null;
    _finishing = false;
    _emit();
    await persist(diagnostic);
  }

  Future<void> cancel({bool interrupted = false}) async {
    final probeId = _activeProbeId;
    if (!isRunning || probeId == null) return;
    await _probeChannel.cancel(probeId);
    if (_activeProbeId != probeId || !isRunning) return;
    final now = DateTime.now().toUtc();
    final probe = CellularInternetProbeResult(
      requestedCellularNetwork: true,
      cellularNetworkAcquired: diagnostic.interfaceAvailable ?? false,
      transportCellularConfirmed: diagnostic.interfaceAvailable ?? false,
      internetCapabilityPresent:
          diagnostic.internetProbe?.internetCapabilityPresent,
      validatedCapabilityPresent:
          diagnostic.internetProbe?.validatedCapabilityPresent,
      probeAttempted: diagnostic.internetProbe?.probeAttempted ?? false,
      responseReceived: false,
      startedAt: diagnostic.startedAt ?? now,
      completedAt: now,
      timeoutReached: false,
      result: CellularInternetProbeOutcome.cancelled,
      errorCode: interrupted ? 'interrupted' : 'cancelledByUser',
      errorMessage: interrupted
          ? 'El diagnóstico fue interrumpido al abandonar la pantalla.'
          : 'El diagnóstico fue cancelado por el técnico.',
      platform: 'android',
      methodVersion: configuration.methodVersion,
    );
    await _finishFromProbe(probeId, probe);
  }

  int _elapsedNow() => diagnostic.startedAt == null
      ? 0
      : DateTime.now()
            .toUtc()
            .difference(diagnostic.startedAt!)
            .inSeconds
            .clamp(0, 60);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopResources() async {
    _countdown?.cancel();
    _countdown = null;
    final probeId = _activeProbeId;
    _activeProbeId = null;
    if (probeId != null) await _probeChannel.cancel(probeId);
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    final probeId = _activeProbeId;
    _activeProbeId = null;
    if (probeId != null) unawaited(_probeChannel.cancel(probeId));
    super.dispose();
  }
}
