import 'package:ddr001diag/domain/measurements/typed_measurement_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convierte las unidades base aprobadas sin redondeo destructivo', () {
    expect(TypedMeasurementCalculator.convert(1, 'bar', 'kPa').value, 100);
    expect(
      TypedMeasurementCalculator.convert(1, 'psi', 'kPa').value,
      closeTo(6.894757293168, 1e-12),
    );
    expect(
      TypedMeasurementCalculator.convert(1, 'm.c.a.', 'kPa').value,
      9.80665,
    );
    expect(TypedMeasurementCalculator.convert(60, 'L/min', 'L/s').value, 1);
    expect(TypedMeasurementCalculator.convert(3.6, 'm³/h', 'L/s').value, 1);
    expect(TypedMeasurementCalculator.convert(1, 'm³', 'L').value, 1000);
  });

  test('calcula estadística y volumen conocidos', () {
    expect(TypedMeasurementCalculator.average([1, 2, 3]).value, 2);
    expect(
      TypedMeasurementCalculator.sampleStandardDeviation([1, 2, 3]).value,
      closeTo(1, 1e-12),
    );
    expect(TypedMeasurementCalculator.percentageError(9, 10).value, 10);
    expect(TypedMeasurementCalculator.volume(2, 30).value, 60);
  });

  test('patrón cero y unidad incompatible son no calculables', () {
    final zero = TypedMeasurementCalculator.percentageError(9, 0);
    final unsupported = TypedMeasurementCalculator.convert(1, 'V', 'kPa');
    expect(zero.calculable, isFalse);
    expect(zero.value, isNull);
    expect(zero.reason, contains('cero'));
    expect(unsupported.calculable, isFalse);
    expect(unsupported.formulaVersion, isNotEmpty);
  });
}
