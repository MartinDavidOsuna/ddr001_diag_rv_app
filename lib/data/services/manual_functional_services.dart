class ManualServiceResult {
  const ManualServiceResult({
    required this.success,
    required this.message,
    this.values = const {},
  });
  final bool success;
  final String message;
  final Map<String, dynamic> values;
}

abstract interface class TelemetryService {
  Future<ManualServiceResult> recordManualCheck(Map<String, dynamic> values);
}

abstract interface class ModbusService {
  Future<ManualServiceResult> recordManualCheck(Map<String, dynamic> values);
}

abstract interface class RemoteActuationService {
  Future<ManualServiceResult> simulate(Map<String, dynamic> values);
}

class ManualTelemetryService implements TelemetryService {
  @override
  Future<ManualServiceResult> recordManualCheck(
    Map<String, dynamic> values,
  ) async => ManualServiceResult(
    success: true,
    message: 'Registro manual; sin conexión de telemetría real.',
    values: values,
  );
}

class ManualModbusService implements ModbusService {
  @override
  Future<ManualServiceResult> recordManualCheck(
    Map<String, dynamic> values,
  ) async => ManualServiceResult(
    success: true,
    message: 'Registro manual; no se envió ningún comando Modbus.',
    values: values,
  );
}

class ManualRemoteActuationService implements RemoteActuationService {
  @override
  Future<ManualServiceResult> simulate(Map<String, dynamic> values) async =>
      ManualServiceResult(
        success: true,
        message: 'Actuación simulada; no se operó equipo real.',
        values: values,
      );
}
