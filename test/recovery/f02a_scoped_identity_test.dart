import 'package:ddr001diag/core/security/f02a_scoped_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalScopeSegment', () {
    const cases = <String, String>{
      'abc-123': 'abc-123',
      'ABC-123': 'abc-123',
      ' ABC-123 ': 'abc-123',
      'HIDRANTE 01': 'hidrante%2001',
      'ABC/123': 'abc%2F123',
      'A+B': 'a%2Bb',
      'A#B': 'a%23b',
      'HIDRANTE ÁRBOL': 'hidrante%20%C3%A1rbol',
    };

    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(canonicalScopeSegment(entry.key), entry.value);
      });
    }

    test('null and blank values are absent', () {
      expect(canonicalScopeSegment(null), isNull);
      expect(canonicalScopeSegment(''), isNull);
      expect(canonicalScopeSegment('   '), isNull);
    });
  });

  group('F02A owner precedence', () {
    test('ownerUserId wins when meaningful', () {
      expect(
        resolveF02AOwnerUserId(
          ownerUserId: 'USER-1',
          createdBy: 'CREATED-1',
          inspectorId: 'INSPECTOR-1',
        ),
        'USER-1',
      );
    });

    test('blank owner falls back to createdBy', () {
      expect(
        resolveF02AOwnerUserId(
          ownerUserId: '',
          createdBy: 'CREATED-1',
          inspectorId: 'INSPECTOR-1',
        ),
        'CREATED-1',
      );
      expect(
        resolveF02AOwnerUserId(
          ownerUserId: '   ',
          createdBy: ' CREATED-1 ',
          inspectorId: 'INSPECTOR-1',
        ),
        'CREATED-1',
      );
    });

    test('blank owner and creator fall back to inspectorId', () {
      expect(
        resolveF02AOwnerUserId(
          ownerUserId: null,
          createdBy: '',
          inspectorId: 'INSPECTOR-1',
        ),
        'INSPECTOR-1',
      );
    });

    test('does not invent an owner', () {
      expect(
        resolveF02AOwnerUserId(
          ownerUserId: null,
          createdBy: ' ',
          inspectorId: ' ',
        ),
        isNull,
      );
    });
  });

  test('buildF02AScopedKey canonicalizes every variable component', () {
    expect(
      buildF02AScopedKey(
        environment: ' Production ',
        accountId: ' DDR 001 ',
        ownerUserId: ' ',
        createdBy: ' CREATED/USER ',
        inspectorId: 'ignored',
        hydrantId: ' A+B#C/01 ',
      ),
      'production/ddr%20001/created%2Fuser/a%2Bb%23c%2F01/f02A',
    );
  });

  test('incomplete identity stays conservative', () {
    expect(
      buildF02AScopedKey(
        environment: 'production',
        accountId: 'account',
        ownerUserId: ' ',
        createdBy: '',
        inspectorId: null,
        hydrantId: 'hydrant',
      ),
      isNull,
    );
  });
}
