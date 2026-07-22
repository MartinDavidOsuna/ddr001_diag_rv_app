import 'dart:math' as math;

enum MeasurementDimension {
  pressure,
  flow,
  volume,
  time,
  voltage,
  current,
  resistance,
  power,
  latency,
}

class NormalizedMeasurement {
  const NormalizedMeasurement({
    required this.originalValue,
    required this.originalUnit,
    required this.normalizedValue,
    required this.baseUnit,
    this.conversionVersion = 'units-v1',
    required this.precision,
  });
  final String originalValue,
      originalUnit,
      normalizedValue,
      baseUnit,
      conversionVersion;
  final int precision;
}

abstract final class MeasurementUnits {
  static const conversionVersion = 'units-v1';
  static const units = <MeasurementDimension, List<String>>{
    MeasurementDimension.pressure: ['kPa', 'bar', 'psi', 'm.c.a.'],
    MeasurementDimension.flow: ['L/s', 'L/min', 'm³/h'],
    MeasurementDimension.volume: ['L', 'm³'],
    MeasurementDimension.time: ['s'],
    MeasurementDimension.voltage: ['V'],
    MeasurementDimension.current: ['A'],
    MeasurementDimension.resistance: ['Ω'],
    MeasurementDimension.power: ['W'],
    MeasurementDimension.latency: ['ms'],
  };
  static String baseUnit(MeasurementDimension dimension) =>
      units[dimension]!.first;
  static NormalizedMeasurement normalize(
    String captured,
    String unit,
    MeasurementDimension dimension,
  ) {
    final trimmed = captured.trim();
    final value = double.tryParse(trimmed.replaceAll(',', '.'));
    if (value == null) throw const FormatException('Valor numérico inválido.');
    final normalized = switch ((dimension, unit)) {
      (MeasurementDimension.pressure, 'bar') => value * 100,
      (MeasurementDimension.pressure, 'psi') => value * 6.894757293168,
      (MeasurementDimension.pressure, 'm.c.a.') => value * 9.80665,
      (MeasurementDimension.flow, 'L/min') => value / 60,
      (MeasurementDimension.flow, 'm³/h') => value / 3.6,
      (MeasurementDimension.volume, 'm³') => value * 1000,
      _ => value,
    };
    final precision = trimmed.contains('.')
        ? trimmed.split('.').last.length
        : trimmed.contains(',')
        ? trimmed.split(',').last.length
        : 0;
    return NormalizedMeasurement(
      originalValue: trimmed,
      originalUnit: unit,
      normalizedValue: _canonical(normalized),
      baseUnit: baseUnit(dimension),
      precision: precision,
    );
  }

  static String _canonical(double value) {
    if (!value.isFinite) throw const FormatException('Resultado no finito.');
    var text = value.toStringAsPrecision(15);
    if (text.contains('e')) return text;
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return text == '-0' ? '0' : text;
  }
}

class SeriesStatistics {
  const SeriesStatistics({
    required this.minimum,
    required this.maximum,
    required this.average,
    required this.range,
    required this.sampleStandardDeviation,
  });
  final double minimum, maximum, average, range;
  final double? sampleStandardDeviation;
  static SeriesStatistics? calculate(Iterable<String> canonicalValues) {
    final values = canonicalValues
        .map(double.tryParse)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList();
    if (values.isEmpty) return null;
    final min = values.reduce(math.min),
        max = values.reduce(math.max),
        average = values.reduce((a, b) => a + b) / values.length;
    double? deviation;
    if (values.length > 1) {
      deviation = math.sqrt(
        values.map((v) => math.pow(v - average, 2)).reduce((a, b) => a + b) /
            (values.length - 1),
      );
    }
    return SeriesStatistics(
      minimum: min,
      maximum: max,
      average: average,
      range: max - min,
      sampleStandardDeviation: deviation,
    );
  }

  static double? absoluteError(double measured, double reference) =>
      measured - reference;
  static double? percentageError(double measured, double reference) =>
      reference == 0
      ? null
      : ((measured - reference).abs() / reference.abs()) * 100;
  static double? derivedVolume({
    required double flowLitersPerSecond,
    required double durationSeconds,
  }) => flowLitersPerSecond * durationSeconds;
}
