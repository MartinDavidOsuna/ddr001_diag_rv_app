import 'dart:io';
import 'package:ddr001diag/features/inspections/domain/filter_element_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('models three states and legacy booleans', () {
    expect(
      FilterElementSelection.fromValue(true).state,
      FilterElementState.present,
    );
    expect(
      FilterElementSelection.fromValue(false).state,
      FilterElementState.absent,
    );
    expect(
      const FilterElementSelection(
        FilterElementState.undetermined,
        undefinedReason: '1234567890',
      ).wireState,
      'undefined',
    );
  });
  test('undefined requires ten trimmed characters', () {
    expect(
      const FilterElementSelection(
        FilterElementState.undetermined,
        undefinedReason: '123456789',
      ).isComplete,
      isFalse,
    );
    expect(
      const FilterElementSelection(
        FilterElementState.undetermined,
        undefinedReason: 'Motivo válido',
      ).isComplete,
      isTrue,
    );
  });
  test('present and absent remove residual reason', () {
    expect(
      const FilterElementSelection(
        FilterElementState.present,
        undefinedReason: 'residual',
      ).toJson()['reason'],
      isNull,
    );
    expect(
      const FilterElementSelection(
        FilterElementState.absent,
        undefinedReason: 'residual',
      ).toJson()['reason'],
      isNull,
    );
  });
  test('renderer is RV-only, offers three labels, reason and no photo', () {
    final source = File(
      'lib/features/checklist/presentation/dynamic_checklist_renderer.dart',
    ).readAsStringSync();
    expect(source, contains("item.code == 'filter_element'"));
    expect(source, contains("Text('Indefinido')"));
    expect(source, contains('Explica por qué no puede determinarse'));
    expect(source, isNot(contains('filter_element_evidence')));
    expect(
      File(
        'lib/features/functional/functional_inspection_page.dart',
      ).readAsStringSync(),
      isNot(contains('FilterElementState')),
    );
  });
}
