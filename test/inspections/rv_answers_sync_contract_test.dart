import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/data/rv_answer_payload_builder.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27);
  const general = ChecklistSectionDefinition(
    id: '11111111-1111-4111-8111-111111111111',
    code: 'general',
    title: 'General',
    order: 1,
    items: [
      ChecklistItemDefinition(
        id: '22222222-2222-4222-8222-222222222222',
        code: 'flow_meter_brand',
        label: 'Marca',
        type: 'text',
        required: true,
        order: 1,
      ),
      ChecklistItemDefinition(
        id: '33333333-3333-4333-8333-333333333333',
        code: 'flow_meter_diameter',
        label: 'Diámetro',
        type: 'decimal',
        required: true,
        order: 2,
      ),
    ],
  );
  const parcel = ChecklistSectionDefinition(
    id: '44444444-4444-4444-8444-444444444444',
    code: 'valvulas_parcelarias',
    title: 'Válvulas',
    order: 8,
    items: [
      ChecklistItemDefinition(
        id: '55555555-5555-4555-8555-555555555555',
        code: 'parcel_valve_count',
        label: 'Cantidad',
        type: 'integer',
        required: true,
        order: 1,
      ),
    ],
  );

  RvDraft draft({required Map<String, RvAnswer> answers}) {
    final checklist = DynamicChecklist(
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      code: 'RV',
      version: 1,
      title: 'RV',
      etag: 'fixture',
      cachedAt: now,
      sections: const [general, parcel],
    );
    return RvDraft(
      clientInspectionId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      hydrantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      accountNumber: 'FIXTURE',
      fieldSessionId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      checklistId: checklist.id,
      checklistVersion: 1,
      checklistSnapshot: checklist.toJson(),
      createdAt: now,
      updatedAt: now,
      answers: answers,
    );
  }

  RvAnswer answer(String id, String type, Object? value) => RvAnswer(
    questionId: id,
    sectionId: general.id,
    answerType: type,
    value: value,
    updatedAt: now,
  );

  const brandId = '66666666-6666-4666-8666-666666666666';
  const diameterId = '30000000-0000-4000-8000-000000000003';

  test('serializa marca remota como texto e ID', () {
    final payload = const RvAnswerPayloadBuilder().build(
      draft(
        answers: {
          general.items[0].id: answer(general.items[0].id, 'text', {
            'catalogId': brandId,
            'localCatalogId': 'local-brand',
            'displayValue': 'MARCA-PRUEBA',
            'elementType': 'FLOW_METER',
          }),
        },
      ),
    );
    expect(payload.single['value'], 'MARCA-PRUEBA');
    expect(payload.single['brandId'], brandId);
  });

  test('serializa diámetro remoto como número, no displayValue', () {
    final payload = const RvAnswerPayloadBuilder().build(
      draft(
        answers: {
          general.items[1].id: answer(general.items[1].id, 'decimal', {
            'catalogId': diameterId,
            'localCatalogId': diameterId,
            'numericValue': 3.0,
            'unit': 'in',
            'displayValue': '3"',
          }),
        },
      ),
    );
    expect(payload.single['value'], 3.0);
    expect(payload.single['diameterId'], diameterId);
  });

  test('bloquea catálogo local no reconciliado antes de red', () {
    expect(
      () => const RvAnswerPayloadBuilder().build(
        draft(
          answers: {
            general.items[0].id: answer(general.items[0].id, 'text', {
              'localCatalogId': 'local-only',
              'displayValue': 'LOCAL',
              'elementType': 'FLOW_METER',
            }),
          },
        ),
      ),
      throwsA(isA<RvPayloadException>()),
    );
  });

  test('excluye completamente los reactivos planos del paso 8', () {
    final payload = const RvAnswerPayloadBuilder().build(
      draft(
        answers: {
          parcel.items.single.id: RvAnswer(
            questionId: parcel.items.single.id,
            sectionId: parcel.id,
            answerType: 'integer',
            value: 3,
            updatedAt: now,
          ),
        },
      ),
    );
    expect(payload, isEmpty);
  });

  test('interpreta RFC Problem, path y request id', () {
    final request = RequestOptions(path: '/inspections/id/answers');
    final exception = ApiException.fromDio(
      DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 422,
          headers: Headers.fromMap({
            'x-request-id': ['request-fixture'],
          }),
          data: {
            'type': 'https://rvs.example/problems/invalid-answer',
            'title': 'Invalid answer',
            'detail': 'flow_meter_diameter: Expected number.',
            'errors': [
              {
                'path': ['answers', 1, 'value'],
                'code': 'invalid_answer_type',
                'message': 'Expected number.',
              },
            ],
          },
        ),
      ),
    );
    expect(exception.kind, ApiErrorKind.validation);
    expect(exception.requestId, 'request-fixture');
    expect(exception.field, 'answers.1.value');
    expect(exception.message, contains('datos no son válidos'));
    expect(exception.message, isNot(contains('Expected number')));
  });
}
