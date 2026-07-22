import 'package:flutter_test/flutter_test.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';

void main() {
  test('round-trip conserva UUID, datos tipados y campos desconocidos', () {
    final now = DateTime.utc(2026, 7, 16);
    final source = VisualComponentInspection(
      id: 'uuid-estable',
      inspectionId: 'rv-1',
      componentDefinitionId: 'gauge-1',
      componentType: VisualComponentType.pressureGauge,
      compartment: VisualCompartment.publicNetwork,
      sequence: 4,
      presenceAnswer: PresenceAnswer.installed,
      visualCondition: VisualComponentCondition.minorFinding,
      observedConditions: const {ObservedCondition.corrosion},
      suggestedDefaultsApplied: true,
      explicitlyConfirmed: true,
      specificData: const VisualComponentSpecificData(
        faceLegible: true,
        visibleRange: '0–10',
        visibleUnit: 'bar',
      ),
      createdAt: now,
      updatedAt: now,
      unknownFields: const {'futureField': 'preservado'},
    );
    final restored = VisualComponentInspection.fromJson(source.toJson());
    expect(restored.id, 'uuid-estable');
    expect(restored.specificData.visibleUnit, 'bar');
    expect(restored.observedConditions, {ObservedCondition.corrosion});
    expect(restored.suggestedDefaultsApplied, isTrue);
    expect(restored.explicitlyConfirmed, isTrue);
    expect(restored.toJson()['futureField'], 'preservado');
  });

  test('lectura anterior usa defaults seguros sin inventar revisión', () {
    final restored = VisualComponentInspection.fromJson({
      'id': 'legacy-id',
      'inspectionId': 'rv-old',
      'componentDefinitionId': 'valve',
      'componentType': 'serviceValve',
      'compartment': 'publicNetwork',
      'sequence': 0,
      'createdAt': '2025-01-01T00:00:00.000Z',
      'updatedAt': '2025-01-01T00:00:00.000Z',
    });
    expect(restored.reviewStatus, ComponentReviewStatus.pending);
    expect(restored.presenceAnswer, isNull);
    expect(restored.visualCondition, isNull);
    expect(restored.explicitlyConfirmed, isFalse);
    expect(restored.isReviewed, isFalse);
  });
}
