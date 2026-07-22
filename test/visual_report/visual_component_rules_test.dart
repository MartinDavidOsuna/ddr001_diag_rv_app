import 'package:flutter_test/flutter_test.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_rules.dart';

VisualComponentInspection component({
  VisualComponentType type = VisualComponentType.serviceValve,
  PresenceAnswer? presence,
  VisualComponentCondition? condition,
  Set<ObservedCondition> observed = const {},
  String comment = '',
  VisualComponentSpecificData data = const VisualComponentSpecificData(),
  bool difference = false,
  List<String> photos = const [],
  bool confirmed = false,
}) => VisualComponentInspection(
  id: 'component-1',
  inspectionId: 'rv-1',
  componentDefinitionId: 'definition-1',
  componentType: type,
  compartment: VisualCompartment.publicNetwork,
  sequence: 1,
  presenceAnswer: presence,
  visualCondition: condition,
  observedConditions: observed,
  comment: comment,
  specificData: data,
  configurationDifference: difference,
  photoIds: photos,
  explicitlyConfirmed: confirmed,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('sin daño visible es incompatible con un daño', () {
    final issues = VisualComponentRules.validate(
      component(
        presence: PresenceAnswer.installed,
        condition: VisualComponentCondition.minorFinding,
        observed: const {
          ObservedCondition.noVisibleDamage,
          ObservedCondition.corrosion,
        },
      ),
      hasValidPhoto: false,
    );
    expect(issues.map((item) => item.code), contains('conditionConflict'));
  });

  test('hallazgo importante exige comentario y fotografía', () {
    final issues = VisualComponentRules.validate(
      component(
        presence: PresenceAnswer.installed,
        condition: VisualComponentCondition.majorFinding,
      ),
      hasValidPhoto: false,
    );
    expect(issues.map((item) => item.code), containsAll(['comment', 'photo']));
  });

  test('manómetro exige legibilidad, rango y unidad visibles', () {
    final issues = VisualComponentRules.validate(
      component(
        type: VisualComponentType.pressureGauge,
        presence: PresenceAnswer.installed,
        condition: VisualComponentCondition.good,
      ),
      hasValidPhoto: true,
    );
    expect(
      issues.map((item) => item.code),
      containsAll(['faceLegible', 'visibleRange', 'visibleUnit']),
    );
  });

  test('revisión rápida no sobrescribe hallazgos ni discrepancias', () {
    final now = DateTime.utc(2026, 7, 16);
    final pending = component();
    final finding = component(
      condition: VisualComponentCondition.critical,
      presence: PresenceAnswer.installed,
      comment: 'Fuga',
    ).copyWith(updatedAt: now);
    final difference = component(difference: true);
    final definitions = {
      'definition-1': const VisualComponentDefinition(
        id: 'definition-1',
        type: VisualComponentType.serviceValve,
        name: 'Válvula',
        shortLabel: 'V',
        compartment: VisualCompartment.publicNetwork,
      ),
    };
    final result = VisualComponentRules.applyQuickReview(
      [pending, finding, difference],
      definitions,
      actor: 'inspector',
      timestamp: now,
    );
    expect(result[0].quickReviewApplied, isTrue);
    expect(result[0].explicitlyConfirmed, isFalse);
    expect(result[0].isReviewed, isFalse);
    expect(result[0].visualCondition, VisualComponentCondition.good);
    expect(result[1].visualCondition, VisualComponentCondition.critical);
    expect(result[2].presenceAnswer, isNull);
  });

  test('defaults favorables no confirman ni generan reviewedAt', () {
    final value = VisualComponentRules.suggestedDefaults(component());
    expect(value.presenceAnswer, PresenceAnswer.installed);
    expect(value.visualCondition, VisualComponentCondition.good);
    expect(value.observedConditions, {ObservedCondition.noVisibleDamage});
    expect(value.suggestedDefaultsApplied, isTrue);
    expect(value.explicitlyConfirmed, isFalse);
    expect(value.isReviewed, isFalse);
    expect(value.reviewedAt, isNull);
  });

  test('solo confirmación explícita establece actor y fecha', () {
    final timestamp = DateTime.utc(2026, 7, 16);
    final value = VisualComponentRules.confirm(
      VisualComponentRules.suggestedDefaults(component()),
      actor: 'inspector',
      timestamp: timestamp,
    );
    expect(value.explicitlyConfirmed, isTrue);
    expect(value.reviewedBy, 'inspector');
    expect(value.reviewedAt, timestamp);
    expect(value.isReviewed, isTrue);
  });

  test('presencia No limpia condición favorable incompatible', () {
    final value = VisualComponentRules.changePresence(
      VisualComponentRules.suggestedDefaults(component()),
      PresenceAnswer.notInstalled,
    );
    expect(value.visualCondition, isNull);
    expect(value.observedConditions, isEmpty);
    expect(value.explicitlyConfirmed, isFalse);
  });

  test('cambiar a hallazgo elimina Sin daño visible', () {
    final value = VisualComponentRules.changeCondition(
      VisualComponentRules.suggestedDefaults(component()),
      VisualComponentCondition.majorFinding,
    );
    expect(
      value.observedConditions,
      isNot(contains(ObservedCondition.noVisibleDamage)),
    );
  });
}
