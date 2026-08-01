import 'dart:io';
import 'package:ddr001diag/features/catalogs/brand_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readable and legacy brand remain readable', () {
    final value = BrandSelection.fromJson({
      'catalogId': 'brand-1',
      'displayValue': 'BERMAD',
    });
    expect(value.mode, BrandReadability.readable);
    expect(value.brandId, 'brand-1');
  });
  test('illegible requires ten trimmed characters and round-trips', () {
    const short = BrandSelection(
      mode: BrandReadability.illegible,
      displayName: 'Ilegible',
      illegibleReason: '123456789',
    );
    const valid = BrandSelection(
      mode: BrandReadability.illegible,
      displayName: 'Ilegible',
      illegibleReason: 'Placa oxidada',
    );
    expect(short.isComplete, isFalse);
    expect(valid.isComplete, isTrue);
    expect(BrandSelection.fromJson(valid.toJson()).brandId, isNull);
  });
  test('all RV brand fields use the special selector and RF is untouched', () {
    final source = File(
      'lib/features/checklist/presentation/dynamic_checklist_renderer.dart',
    ).readAsStringSync();
    expect(source, contains('Ilegible · condición especial'));
    expect(source, contains('valveBrand: illegibleBrandMap'));
    expect(source, contains('solenoidBrand: illegibleBrandMap'));
    expect(source, contains('pilotBrand: illegibleBrandMap'));
    expect(source, contains('pressureGaugeBrand: illegibleBrandMap'));
    expect(
      File(
        'lib/features/functional/functional_inspection_page.dart',
      ).readAsStringSync(),
      isNot(contains('BrandReadability')),
    );
  });
}
