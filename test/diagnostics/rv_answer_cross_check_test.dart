import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/diagnostics/rv_answer_cross_check.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const itemId = '22222222-2222-4222-8222-222222222222';
  final now = DateTime.utc(2026, 8, 28);
  final checklist = DynamicChecklist(
    id: '11111111-1111-4111-8111-111111111111',
    code: 'RV',
    version: 1,
    title: 'RV',
    etag: 'fixture',
    cachedAt: now,
    sections: const [
      ChecklistSectionDefinition(
        id: '33333333-3333-4333-8333-333333333333',
        code: 'general',
        title: 'General',
        order: 1,
        items: [
          ChecklistItemDefinition(
            id: itemId,
            code: 'visible',
            label: 'Visible',
            type: 'boolean',
            required: true,
            order: 1,
          ),
        ],
      ),
    ],
  );
  final draft = RvDraft(
    clientInspectionId: '44444444-4444-4444-8444-444444444444',
    hydrantId: '55555555-5555-4555-8555-555555555555',
    accountNumber: '1000',
    fieldSessionId: '66666666-6666-4666-8666-666666666666',
    checklistId: checklist.id,
    checklistVersion: checklist.version,
    checklistSnapshot: checklist.toJson(),
    answers: {
      itemId: RvAnswer(
        questionId: itemId,
        sectionId: checklist.sections.single.id,
        answerType: 'boolean',
        value: true,
        updatedAt: now,
      ),
    },
    createdAt: now,
    updatedAt: now,
  );

  test('compara el 100% por UUID sin sensibilidad a casing', () {
    final result = buildRvAnswerCrossCheck(draft, [
      {
        'item_id': itemId.toUpperCase(),
        'value_boolean': 1,
        'is_not_applicable': false,
      },
    ]);

    expect(result['localCapturedCount'], 1);
    expect(result['remoteContractCount'], 1);
    expect(result['match'], isTrue);
    expect(result['missingRemoteItemIds'], isEmpty);
    expect(result['divergentItemIds'], isEmpty);
  });

  test('diferencia real queda identificada sin inventar respuesta', () {
    final result = buildRvAnswerCrossCheck(draft, [
      {'item_id': itemId, 'value_boolean': 0, 'is_not_applicable': false},
    ]);

    expect(result['match'], isFalse);
    expect(result['divergentItemIds'], [itemId]);
  });
}
