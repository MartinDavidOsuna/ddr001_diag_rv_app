import 'package:ddr001diag/features/inspections/domain/hydrant_account_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transformLegacyHyphenAccount follows the exact legacy rule', () {
    expect(transformLegacyHyphenAccount('352-1'), '3520001');
    expect(transformLegacyHyphenAccount('486-2'), '4860002');
    expect(transformLegacyHyphenAccount('367-2'), '3670002');
    expect(transformLegacyHyphenAccount('472-2'), '4720002');
    expect(transformLegacyHyphenAccount('462-1'), '4620001');
    expect(transformLegacyHyphenAccount('1134'), '1134');
    expect(transformLegacyHyphenAccount('35-2-1'), '3500020001');
  });

  test('transformation is idempotent', () {
    for (final value in ['352-1', '486-2', '1134', '35-2-1']) {
      final once = transformLegacyHyphenAccount(value);
      expect(transformLegacyHyphenAccount(once), once);
    }
  });

  test(
    'alias is forbidden until original incompatibility and collision proof',
    () {
      bool allowed({
        bool absent = true,
        bool incompatible = true,
        bool checked = true,
        bool collision = false,
      }) => mayUseLegacyHyphenAlias(
        originalAccountNumber: '352-1',
        originalAbsent: absent,
        originalCreateHyphenIncompatible: incompatible,
        aliasCollisionChecked: checked,
        aliasBelongsToDifferentHydrant: collision,
      );

      expect(allowed(), isTrue);
      expect(allowed(absent: false), isFalse);
      expect(allowed(incompatible: false), isFalse);
      expect(allowed(checked: false), isFalse);
      expect(allowed(collision: true), isFalse);
    },
  );

  test('identity preserves original and reversible metadata', () {
    final at = DateTime.utc(2026, 8, 18);
    final identity = HydrantAccountIdentity(
      originalAccountNumber: '486-2',
      effectiveAccountNumber: '4860002',
      transformation: AccountTransformation.hyphenTo000,
      transformationVersion: 1,
      transformedAt: at,
      resolutionState: AccountResolutionState.transformed,
    );
    final restored = HydrantAccountIdentity.fromJson(
      identity.toJson(),
      legacyAccountNumber: 'unused',
    );
    expect(restored.originalAccountNumber, '486-2');
    expect(restored.effectiveAccountNumber, '4860002');
    expect(restored.transformationVersion, 1);
    expect(restored.transformedAt, at);
  });
}
