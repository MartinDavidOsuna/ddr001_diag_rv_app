import 'dart:math' as math;

class CalculationResult {
  const CalculationResult({
    this.value,
    required this.unit,
    required this.calculable,
    required this.reason,
    required this.formulaVersion,
    required this.toleranceVersion,
    required this.calculatedAt,
  });
  final double? value;
  final String unit, reason, formulaVersion, toleranceVersion;
  final bool calculable;
  final DateTime calculatedAt;
}

class TypedMeasurementCalculator {
  const TypedMeasurementCalculator._();
  static const formulaVersion = 'measurements-v1';

  static CalculationResult convert(double value, String from, String to) {
    final base = switch (from) {
      'bar' => value * 100,
      'psi' => value * 6.894757293168,
      'm.c.a.' => value * 9.80665,
      'kPa' => value,
      'L/min' => value / 60,
      'm³/h' => value / 3.6,
      'L/s' => value,
      'm³' => value * 1000,
      'L' => value,
      _ => double.nan,
    };
    final converted = switch (to) {
      'kPa' when {'bar', 'psi', 'm.c.a.', 'kPa'}.contains(from) => base,
      'L/s' when {'L/min', 'm³/h', 'L/s'}.contains(from) => base,
      'L' when {'m³', 'L'}.contains(from) => base,
      _ => double.nan,
    };
    return _result(converted, to, 'Conversión $from→$to');
  }

  static CalculationResult average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return _notCalculable('', 'Sin valores');
    return _result(list.reduce((a, b) => a + b) / list.length, '', 'Promedio');
  }

  static CalculationResult sampleStandardDeviation(Iterable<double> values) {
    final list = values.toList();
    if (list.length < 2) {
      return _notCalculable('', 'Se requieren al menos dos valores');
    }
    final mean = list.reduce((a, b) => a + b) / list.length;
    final sum = list.fold<double>(0, (v, x) => v + math.pow(x - mean, 2));
    return _result(
      math.sqrt(sum / (list.length - 1)),
      '',
      'Desviación muestral',
    );
  }

  static CalculationResult percentageError(double measured, double pattern) {
    if (pattern == 0) return _notCalculable('%', 'Patrón igual a cero');
    return _result(
      (measured - pattern).abs() / pattern.abs() * 100,
      '%',
      'Error porcentual',
    );
  }

  static CalculationResult volume(double flowLitersPerSecond, double seconds) =>
      _result(flowLitersPerSecond * seconds, 'L', 'Volumen=caudal×tiempo');

  static CalculationResult _result(double value, String unit, String reason) {
    if (!value.isFinite) return _notCalculable(unit, 'Unidad no soportada');
    return CalculationResult(
      value: value,
      unit: unit,
      calculable: true,
      reason: reason,
      formulaVersion: formulaVersion,
      toleranceVersion: 'demo-tolerances-v1',
      calculatedAt: DateTime.now().toUtc(),
    );
  }

  static CalculationResult _notCalculable(String unit, String reason) =>
      CalculationResult(
        unit: unit,
        calculable: false,
        reason: reason,
        formulaVersion: formulaVersion,
        toleranceVersion: 'demo-tolerances-v1',
        calculatedAt: DateTime.now().toUtc(),
      );
}
