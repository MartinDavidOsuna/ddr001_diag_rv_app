import '../../domain/functional/functional_models.dart';

class DemoTolerance {
  const DemoTolerance({
    required this.id,
    required this.testType,
    required this.maximumDeviationPercent,
    this.version = 'demo-functional-v1',
    this.isOfficial = false,
  });
  final String id, testType, version;
  final double maximumDeviationPercent;
  final bool isOfficial;
}

abstract final class FunctionalCatalogs {
  static const schemaVersion = 1;
  static const toleranceNotice = 'Tolerancias DEMO · resultado no oficial';
  static const instrumentTypes = [
    'Manómetro',
    'Caudalímetro patrón',
    'Banco de prueba',
    'Multímetro',
    'Pinza amperimétrica',
    'Fuente de alimentación',
    'Simulador de señal',
    'Módem de prueba',
    'Dispositivo Modbus',
    'Herramienta mecánica',
    'Otro',
  ];
  static const pressureUnits = ['kPa', 'bar', 'psi', 'm.c.a.'];
  static const flowUnits = ['L/s', 'L/min', 'm³/h'];
  static const volumeUnits = ['L', 'm³'];
  static const alarmTypes = [
    'Fuga',
    'Presión alta',
    'Presión baja',
    'Caudal fuera de rango',
    'Pérdida de energía',
    'Pérdida de comunicación',
    'Apertura no autorizada',
    'Fallo de sensor',
    'Batería baja',
    'Gabinete abierto',
    'Otra',
  ];
  static const evidenceCategories = [
    'montaje general',
    'banco de pruebas',
    'instrumentos',
    'manómetros',
    'caudalímetro patrón',
    'conexión',
    'presión',
    'caudal',
    'válvula abierta',
    'válvula cerrada',
    'reductora',
    'solenoide',
    'energía',
    'comunicación',
    'telemetría',
    'alarma',
    'fuga',
    'reparación',
    'estado final',
    'otro',
  ];
  static const demoTolerances = [
    DemoTolerance(
      id: 'flow-pattern-demo',
      testType: 'flow',
      maximumDeviationPercent: 5,
    ),
    DemoTolerance(
      id: 'pressure-stability-demo',
      testType: 'pressure',
      maximumDeviationPercent: 5,
    ),
  ];
  static bool calibrationBlocksOfficialMeasurement(
    String instrumentType,
    CalibrationStatus status,
  ) =>
      (instrumentType == 'Manómetro' ||
          instrumentType == 'Caudalímetro patrón') &&
      (status == CalibrationStatus.expired ||
          status == CalibrationStatus.unknown);
}
