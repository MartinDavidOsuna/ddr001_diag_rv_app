import 'package:ddr001diag/features/catalogs/brand_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBrandName', () {
    test('stores and displays every casing variant in uppercase', () {
      expect(normalizeBrandName('Bermad'), 'BERMAD');
      expect(normalizeBrandName(' bermad '), 'BERMAD');
      expect(normalizeBrandName('BERMAD  '), 'BERMAD');
    });

    test('collapses whitespace and preserves legitimate internal hyphens', () {
      expect(normalizeBrandName('  Cla-Val   México '), 'CLA-VAL MÉXICO');
    });

    test('rejects an empty or whitespace-only brand', () {
      expect(() => normalizeBrandName('   '), throwsFormatException);
    });
  });
}
