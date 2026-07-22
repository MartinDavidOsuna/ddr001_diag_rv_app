enum CellularDiagnosticStatus {
  idle,
  preparing,
  analyzing,
  available,
  noCellularNetworksAvailable,
  indeterminate,
  cancelled,
  failed,
}

enum CellularDiagnosticStage {
  preparing,
  checkingPermissions,
  requestingCellularNetwork,
  waitingForAvailability,
  verifyingCapabilities,
  testingInternet,
  measuringResponse,
  calculatingResult,
  completed,
}

enum CellularInternetStatus {
  available,
  unavailable,
  indeterminate,
  pending,
  cancelled,
}

enum CellularInternetProbeOutcome {
  cellularInternetConfirmed,
  cellularNetworkAvailableInternetNotConfirmed,
  cellularNetworkUnavailable,
  endpointUnavailable,
  timeout,
  tlsError,
  unexpectedHttpResponse,
  platformRestricted,
  cancelled,
  indeterminate,
}

class CellularInternetProbeResult {
  const CellularInternetProbeResult({
    required this.requestedCellularNetwork,
    required this.cellularNetworkAcquired,
    required this.transportCellularConfirmed,
    required this.internetCapabilityPresent,
    required this.validatedCapabilityPresent,
    required this.probeAttempted,
    required this.responseReceived,
    required this.startedAt,
    required this.completedAt,
    required this.timeoutReached,
    required this.result,
    required this.platform,
    required this.methodVersion,
    this.probeUrlHost,
    this.httpMethod,
    this.httpStatusCode,
    this.latencyMs,
    this.bytesReceived,
    this.errorCode,
    this.errorMessage,
  });

  final bool requestedCellularNetwork;
  final bool cellularNetworkAcquired;
  final bool transportCellularConfirmed;
  final bool? internetCapabilityPresent;
  final bool? validatedCapabilityPresent;
  final bool probeAttempted;
  final String? probeUrlHost, httpMethod;
  final int? httpStatusCode, latencyMs, bytesReceived;
  final bool responseReceived;
  final DateTime startedAt, completedAt;
  final bool timeoutReached;
  final CellularInternetProbeOutcome result;
  final String? errorCode, errorMessage;
  final String platform, methodVersion;

  bool get confirmsCellularInternet =>
      result == CellularInternetProbeOutcome.cellularInternetConfirmed &&
      cellularNetworkAcquired &&
      transportCellularConfirmed &&
      responseReceived;

  Map<String, dynamic> toJson() => {
    'requestedCellularNetwork': requestedCellularNetwork,
    'cellularNetworkAcquired': cellularNetworkAcquired,
    'transportCellularConfirmed': transportCellularConfirmed,
    'internetCapabilityPresent': internetCapabilityPresent,
    'validatedCapabilityPresent': validatedCapabilityPresent,
    'probeAttempted': probeAttempted,
    'probeUrlHost': probeUrlHost,
    'httpMethod': httpMethod,
    'httpStatusCode': httpStatusCode,
    'responseReceived': responseReceived,
    'latencyMs': latencyMs,
    'bytesReceived': bytesReceived,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'timeoutReached': timeoutReached,
    'result': result.name,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'platform': platform,
    'methodVersion': methodVersion,
  };

  factory CellularInternetProbeResult.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return CellularInternetProbeResult(
      requestedCellularNetwork:
          json['requestedCellularNetwork'] as bool? ?? false,
      cellularNetworkAcquired:
          json['cellularNetworkAcquired'] as bool? ?? false,
      transportCellularConfirmed:
          json['transportCellularConfirmed'] as bool? ?? false,
      internetCapabilityPresent: json['internetCapabilityPresent'] as bool?,
      validatedCapabilityPresent: json['validatedCapabilityPresent'] as bool?,
      probeAttempted: json['probeAttempted'] as bool? ?? false,
      probeUrlHost: json['probeUrlHost'] as String?,
      httpMethod: json['httpMethod'] as String?,
      httpStatusCode: json['httpStatusCode'] as int?,
      responseReceived: json['responseReceived'] as bool? ?? false,
      latencyMs: json['latencyMs'] as int?,
      bytesReceived: json['bytesReceived'] as int?,
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '')?.toUtc() ?? now,
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '')?.toUtc() ??
          now,
      timeoutReached: json['timeoutReached'] as bool? ?? false,
      result: _enumValue(
        CellularInternetProbeOutcome.values,
        json['result'],
        CellularInternetProbeOutcome.indeterminate,
      ),
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      platform: json['platform'] as String? ?? 'unknown',
      methodVersion: json['methodVersion'] as String? ?? 'unknown',
    );
  }

  factory CellularInternetProbeResult.platformRestricted({
    required String methodVersion,
    required String platform,
  }) {
    final now = DateTime.now().toUtc();
    return CellularInternetProbeResult(
      requestedCellularNetwork: false,
      cellularNetworkAcquired: false,
      transportCellularConfirmed: false,
      internetCapabilityPresent: null,
      validatedCapabilityPresent: null,
      probeAttempted: false,
      responseReceived: false,
      startedAt: now,
      completedAt: now,
      timeoutReached: false,
      result: CellularInternetProbeOutcome.platformRestricted,
      errorCode: 'platformRestricted',
      errorMessage:
          'La plataforma no garantiza una solicitud aislada sobre red celular.',
      platform: platform,
      methodVersion: methodVersion,
    );
  }

  factory CellularInternetProbeResult.platformError({
    required String methodVersion,
    required String platform,
    required String code,
    String? message,
  }) {
    final now = DateTime.now().toUtc();
    return CellularInternetProbeResult(
      requestedCellularNetwork: true,
      cellularNetworkAcquired: false,
      transportCellularConfirmed: false,
      internetCapabilityPresent: null,
      validatedCapabilityPresent: null,
      probeAttempted: false,
      responseReceived: false,
      startedAt: now,
      completedAt: now,
      timeoutReached: false,
      result: CellularInternetProbeOutcome.indeterminate,
      errorCode: code,
      errorMessage: message,
      platform: platform,
      methodVersion: methodVersion,
    );
  }
}

class CellularEffectivenessResult {
  const CellularEffectivenessResult({
    required this.formulaVersion,
    required this.indicatorsUsed,
    required this.indicatorsNotAvailable,
    required this.calculable,
    this.percentage,
    this.reason,
  });
  final String formulaVersion;
  final List<String> indicatorsUsed, indicatorsNotAvailable;
  final double? percentage;
  final bool calculable;
  final String? reason;

  Map<String, dynamic> toJson() => {
    'formulaVersion': formulaVersion,
    'indicatorsUsed': indicatorsUsed,
    'indicatorsNotAvailable': indicatorsNotAvailable,
    'percentage': percentage,
    'calculable': calculable,
    'reason': reason,
  };

  factory CellularEffectivenessResult.fromJson(Map<String, dynamic> json) =>
      CellularEffectivenessResult(
        formulaVersion: json['formulaVersion'] as String? ?? 'unknown',
        indicatorsUsed: (json['indicatorsUsed'] as List? ?? []).cast<String>(),
        indicatorsNotAvailable: (json['indicatorsNotAvailable'] as List? ?? [])
            .cast<String>(),
        percentage: (json['percentage'] as num?)?.toDouble(),
        calculable: json['calculable'] as bool? ?? false,
        reason: json['reason'] as String?,
      );
}

class CellularNetworkDiagnostic {
  const CellularNetworkDiagnostic({
    required this.id,
    required this.inspectionId,
    this.status = CellularDiagnosticStatus.idle,
    this.stage = CellularDiagnosticStage.preparing,
    this.startedAt,
    this.completedAt,
    this.timeoutSeconds = 60,
    this.elapsedSeconds = 0,
    this.remainingSeconds = 60,
    this.timeoutReached = false,
    this.interfaceAvailable,
    this.registeredOnNetwork,
    this.operatorName,
    this.networkTechnology,
    this.signalValue,
    this.signalUnit,
    this.qualityScore,
    this.qualityLabel,
    this.internetStatus = CellularInternetStatus.pending,
    this.latencyMs,
    this.attempts = 0,
    this.successfulAttempts = 0,
    this.effectivenessPercentage,
    this.internetProbe,
    this.effectivenessEvidence,
    this.method = 'cellular-diagnostics-demo-v1',
    this.errorCode,
    this.errorMessage,
    this.permissionState = 'notRequiredByCurrentApi',
    this.platformLimitations = const [],
    this.progress = 0,
    this.schemaVersion = 2,
  });

  final String id, inspectionId, method, permissionState;
  final CellularDiagnosticStatus status;
  final CellularDiagnosticStage stage;
  final DateTime? startedAt, completedAt;
  final int timeoutSeconds, elapsedSeconds, remainingSeconds, attempts;
  final int successfulAttempts, schemaVersion;
  final bool timeoutReached;
  final bool? interfaceAvailable, registeredOnNetwork;
  final String? operatorName, networkTechnology, signalUnit, qualityLabel;
  final String? errorCode, errorMessage;
  final double? signalValue, effectivenessPercentage, progress;
  final int? qualityScore, latencyMs;
  final CellularInternetProbeResult? internetProbe;
  final CellularEffectivenessResult? effectivenessEvidence;
  final CellularInternetStatus internetStatus;
  final List<String> platformLimitations;

  bool get isRunning =>
      status == CellularDiagnosticStatus.preparing ||
      status == CellularDiagnosticStatus.analyzing;

  CellularNetworkDiagnostic copyWith({
    CellularDiagnosticStatus? status,
    CellularDiagnosticStage? stage,
    DateTime? startedAt,
    DateTime? completedAt,
    int? elapsedSeconds,
    int? remainingSeconds,
    bool? timeoutReached,
    bool? interfaceAvailable,
    bool? registeredOnNetwork,
    String? operatorName,
    String? networkTechnology,
    double? signalValue,
    String? signalUnit,
    int? qualityScore,
    String? qualityLabel,
    CellularInternetStatus? internetStatus,
    int? latencyMs,
    int? attempts,
    int? successfulAttempts,
    double? effectivenessPercentage,
    CellularInternetProbeResult? internetProbe,
    CellularEffectivenessResult? effectivenessEvidence,
    String? errorCode,
    String? errorMessage,
    List<String>? platformLimitations,
    double? progress,
  }) => CellularNetworkDiagnostic(
    id: id,
    inspectionId: inspectionId,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    timeoutSeconds: timeoutSeconds,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    timeoutReached: timeoutReached ?? this.timeoutReached,
    interfaceAvailable: interfaceAvailable ?? this.interfaceAvailable,
    registeredOnNetwork: registeredOnNetwork ?? this.registeredOnNetwork,
    operatorName: operatorName ?? this.operatorName,
    networkTechnology: networkTechnology ?? this.networkTechnology,
    signalValue: signalValue ?? this.signalValue,
    signalUnit: signalUnit ?? this.signalUnit,
    qualityScore: qualityScore ?? this.qualityScore,
    qualityLabel: qualityLabel ?? this.qualityLabel,
    internetStatus: internetStatus ?? this.internetStatus,
    latencyMs: latencyMs ?? this.latencyMs,
    attempts: attempts ?? this.attempts,
    successfulAttempts: successfulAttempts ?? this.successfulAttempts,
    effectivenessPercentage:
        effectivenessPercentage ?? this.effectivenessPercentage,
    internetProbe: internetProbe ?? this.internetProbe,
    effectivenessEvidence: effectivenessEvidence ?? this.effectivenessEvidence,
    method: method,
    errorCode: errorCode ?? this.errorCode,
    errorMessage: errorMessage ?? this.errorMessage,
    permissionState: permissionState,
    platformLimitations: platformLimitations ?? this.platformLimitations,
    progress: progress ?? this.progress,
    schemaVersion: schemaVersion,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'status': status.name,
    'stage': stage.name,
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'timeoutSeconds': timeoutSeconds,
    'elapsedSeconds': elapsedSeconds,
    'remainingSeconds': remainingSeconds,
    'timeoutReached': timeoutReached,
    'interfaceAvailable': interfaceAvailable,
    'registeredOnNetwork': registeredOnNetwork,
    'operatorName': operatorName,
    'networkTechnology': networkTechnology,
    'signalValue': signalValue,
    'signalUnit': signalUnit,
    'qualityScore': qualityScore,
    'qualityLabel': qualityLabel,
    'internetStatus': internetStatus.name,
    'latencyMs': latencyMs,
    'attempts': attempts,
    'successfulAttempts': successfulAttempts,
    'effectivenessPercentage': effectivenessPercentage,
    'internetProbe': internetProbe?.toJson(),
    'effectivenessEvidence': effectivenessEvidence?.toJson(),
    'method': method,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'permissionState': permissionState,
    'platformLimitations': platformLimitations,
    'progress': progress,
    'schemaVersion': schemaVersion,
  };

  factory CellularNetworkDiagnostic.fromJson(Map<String, dynamic> json) =>
      CellularNetworkDiagnostic(
        id: json['id'] as String? ?? '',
        inspectionId: json['inspectionId'] as String? ?? '',
        status: _enumValue(
          CellularDiagnosticStatus.values,
          json['status'],
          CellularDiagnosticStatus.idle,
        ),
        stage: _enumValue(
          CellularDiagnosticStage.values,
          json['stage'],
          CellularDiagnosticStage.preparing,
        ),
        startedAt: DateTime.tryParse(
          json['startedAt'] as String? ?? '',
        )?.toUtc(),
        completedAt: DateTime.tryParse(
          json['completedAt'] as String? ?? '',
        )?.toUtc(),
        timeoutSeconds: json['timeoutSeconds'] as int? ?? 60,
        elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
        remainingSeconds: json['remainingSeconds'] as int? ?? 60,
        timeoutReached: json['timeoutReached'] as bool? ?? false,
        interfaceAvailable: json['interfaceAvailable'] as bool?,
        registeredOnNetwork: json['registeredOnNetwork'] as bool?,
        operatorName: json['operatorName'] as String?,
        networkTechnology: json['networkTechnology'] as String?,
        signalValue: (json['signalValue'] as num?)?.toDouble(),
        signalUnit: json['signalUnit'] as String?,
        qualityScore: json['qualityScore'] as int?,
        qualityLabel: json['qualityLabel'] as String?,
        internetStatus: _enumValue(
          CellularInternetStatus.values,
          json['internetStatus'],
          CellularInternetStatus.pending,
        ),
        latencyMs: json['latencyMs'] as int?,
        attempts: json['attempts'] as int? ?? 0,
        successfulAttempts: json['successfulAttempts'] as int? ?? 0,
        effectivenessPercentage: (json['effectivenessPercentage'] as num?)
            ?.toDouble(),
        internetProbe: json['internetProbe'] is Map
            ? CellularInternetProbeResult.fromJson(
                Map<String, dynamic>.from(json['internetProbe'] as Map),
              )
            : null,
        effectivenessEvidence: json['effectivenessEvidence'] is Map
            ? CellularEffectivenessResult.fromJson(
                Map<String, dynamic>.from(json['effectivenessEvidence'] as Map),
              )
            : null,
        method: json['method'] as String? ?? 'cellular-diagnostics-demo-v1',
        errorCode: json['errorCode'] as String?,
        errorMessage: json['errorMessage'] as String?,
        permissionState:
            json['permissionState'] as String? ?? 'notRequiredByCurrentApi',
        platformLimitations: (json['platformLimitations'] as List? ?? [])
            .cast<String>(),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );
}

class CellularNetworkQualityCalculator {
  const CellularNetworkQualityCalculator._();
  static const version = 'cellular-quality-demo-v1';

  static int? qualityFromDbm(double? dbm) {
    if (dbm == null) return null;
    if (dbm >= -70) return 10;
    if (dbm <= -120) return 1;
    return (((dbm + 120) / 50) * 9 + 1).round().clamp(1, 10);
  }

  static String? label(int? score) => switch (score) {
    1 || 2 => 'Muy mala',
    3 || 4 => 'Mala',
    5 || 6 => 'Regular',
    7 || 8 => 'Buena',
    9 || 10 => 'Excelente',
    _ => null,
  };

  static CellularEffectivenessResult effectiveness({
    required CellularInternetProbeResult probe,
    required int attempts,
    required int successfulAttempts,
  }) {
    const formulaVersion = 'cellular-effectiveness-demo-v2';
    final known = <({String key, double earned, double possible})>[
      (
        key: 'cellularNetworkAcquired',
        earned: probe.cellularNetworkAcquired ? 20 : 0,
        possible: 20,
      ),
      (
        key: 'transportCellularConfirmed',
        earned: probe.transportCellularConfirmed ? 15 : 0,
        possible: 15,
      ),
    ];
    final unavailable = <String>[];
    if (probe.internetCapabilityPresent == null) {
      unavailable.add('internetCapabilityPresent');
    } else {
      known.add((
        key: 'internetCapabilityPresent',
        earned: probe.internetCapabilityPresent! ? 15 : 0,
        possible: 15,
      ));
    }
    if (probe.validatedCapabilityPresent == null) {
      unavailable.add('validatedCapabilityPresent');
    } else {
      known.add((
        key: 'validatedCapabilityPresent',
        earned: probe.validatedCapabilityPresent! ? 15 : 0,
        possible: 15,
      ));
    }
    if (probe.probeAttempted) {
      known.add((
        key: 'httpResponse',
        earned: probe.confirmsCellularInternet ? 25 : 0,
        possible: 25,
      ));
    } else {
      unavailable.add('httpResponse');
    }
    if (probe.latencyMs != null && probe.responseReceived) {
      final latencyScore = probe.latencyMs! <= 300
          ? 10.0
          : probe.latencyMs! <= 1000
          ? 6.0
          : 2.0;
      known.add((key: 'latency', earned: latencyScore, possible: 10));
    } else {
      unavailable.add('latency');
    }
    if (attempts > 0) {
      known.add((
        key: 'attemptStability',
        earned: (successfulAttempts / attempts).clamp(0, 1) * 5,
        possible: 5,
      ));
    }
    if (known.length < 4) {
      return CellularEffectivenessResult(
        formulaVersion: formulaVersion,
        indicatorsUsed: known.map((item) => item.key).toList(),
        indicatorsNotAvailable: unavailable,
        calculable: false,
        reason: 'Evidencia insuficiente para calcular la efectividad GPRS.',
      );
    }
    final earned = known.fold<double>(0, (sum, item) => sum + item.earned);
    final possible = known.fold<double>(0, (sum, item) => sum + item.possible);
    return CellularEffectivenessResult(
      formulaVersion: formulaVersion,
      indicatorsUsed: known.map((item) => item.key).toList(),
      indicatorsNotAvailable: unavailable,
      calculable: true,
      percentage: (earned / possible * 100).clamp(0, 100),
    );
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;
