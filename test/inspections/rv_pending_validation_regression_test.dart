import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 8);
  const section = ChecklistSectionDefinition(
    id: 'section-meter',
    code: 'meter',
    title: 'Medidor',
    order: 4,
    items: [
      ChecklistItemDefinition(
        id: 'brand',
        code: 'flow_meter_brand',
        label: 'Marca',
        type: 'text',
        required: true,
        order: 1,
      ),
      ChecklistItemDefinition(
        id: 'range',
        code: 'sustaining_gauge_range',
        label: 'Rango del manómetro sostenedor',
        type: 'decimal',
        required: true,
        order: 2,
      ),
      ChecklistItemDefinition(
        id: 'diameter',
        code: 'flow_meter_diameter',
        label: 'Diámetro',
        type: 'decimal',
        required: true,
        order: 3,
      ),
    ],
  );

  RvAnswer answer(String id, Object value) => RvAnswer(
    questionId: id,
    sectionId: section.id,
    answerType: const {'range', 'diameter'}.contains(id) ? 'decimal' : 'text',
    value: value,
    updatedAt: now,
  );

  RvDraft draft(Map<String, RvAnswer> answers) {
    final checklist = DynamicChecklist(
      id: 'checklist',
      code: 'RV',
      version: 2,
      title: 'RV',
      etag: 'fixture',
      cachedAt: now,
      sections: const [section],
    );
    return RvDraft(
      clientInspectionId: 'inspection',
      hydrantId: 'hydrant',
      accountNumber: '1001',
      fieldSessionId: 'session',
      checklistId: checklist.id,
      checklistVersion: checklist.version,
      checklistSnapshot: checklist.toJson(),
      createdAt: now,
      updatedAt: now,
      answers: answers,
    );
  }

  test('una marca ilegible válida no vuelve a aparecer como pendiente', () {
    final issues = const RvValidator()
        .validate(
          draft({
            'brand': answer('brand', {
              'mode': 'illegible',
              'brandId': null,
              'reason': 'La placa está totalmente oxidada',
            }),
          }),
        )
        .issues;

    expect(issues.where((issue) => issue.questionId == 'brand'), isEmpty);
  });

  test('una marca ilegible incompleta explica el dato exacto pendiente', () {
    final issues = const RvValidator()
        .validate(
          draft({
            'brand': answer('brand', {
              'mode': 'illegible',
              'brandId': null,
              'reason': 'no se ve',
            }),
          }),
        )
        .issues;

    expect(
      issues.singleWhere((issue) => issue.questionId == 'brand').message,
      'Describe por qué la marca es ilegible (mínimo 10 caracteres).',
    );
  });

  test(
    'un rango tipado seleccionado es válido aunque el reactivo sea decimal',
    () {
      final issues = const RvValidator()
          .validate(
            draft({
              'range': answer('range', {
                'catalogId': 'range-id',
                'localCatalogId': 'range-local-id',
                'minimum': 0,
                'maximum': 160,
                'unit': 'psi',
                'displayValue': '0–160 psi',
              }),
            }),
          )
          .issues;

      expect(issues.where((issue) => issue.questionId == 'range'), isEmpty);
    },
  );

  test('marca y diámetro seleccionados localmente cuentan como cubiertos', () {
    final issues = const RvValidator()
        .validate(
          draft({
            'brand': answer('brand', {
              'mode': 'readable',
              'localCatalogId': 'brand-local-id',
              'displayValue': 'MARCA LOCAL',
              'elementType': 'FLOW_METER',
            }),
            'diameter': answer('diameter', {
              'localCatalogId': 'diameter-local-id',
              'nominalValue': 2,
              'unit': 'in',
              'displayValue': '2"',
            }),
          }),
        )
        .issues;

    expect(
      issues.where(
        (issue) => const {'brand', 'diameter'}.contains(issue.questionId),
      ),
      isEmpty,
    );
  });
}
