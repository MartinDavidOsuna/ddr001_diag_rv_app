import 'dart:io';
import 'package:ddr001diag/features/inspections/domain/parcel_valve_configuration.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parcel pilot connection round-trip distinguishes true false and null',
    () {
      for (final value in <bool?>[true, false, null]) {
        final valve = ParcelValve(
          index: 1,
          hasPilot: true,
          pilotConnected: value,
        );
        expect(ParcelValve.fromJson(valve.toJson()).pilotConnected, value);
      }
    },
  );

  test('removing a pilot clears only its active connection answer', () {
    final valve = const ParcelValve(
      index: 1,
      hasPilot: true,
      pilotConnected: false,
    ).copyWith(hasPilot: false);
    expect(valve.hasPilot, isFalse);
    expect(valve.pilotConnected, isNull);
  });

  test(
    'visual pilot snapshot preserves connection and legacy remains null',
    () {
      final captured = VisualComponentSpecificData.fromJson({
        'pilotConnected': false,
      });
      expect(captured.pilotConnected, isFalse);
      expect(
        VisualComponentSpecificData.fromJson(const {}).pilotConnected,
        isNull,
      );
      expect(captured.toJson()['pilotConnected'], isFalse);
    },
  );

  test('visual pilot cannot be confirmed without a binary answer', () {
    VisualComponentInspection pilot(VisualComponentSpecificData data) =>
        VisualComponentInspection(
          id: 'pilot-1',
          inspectionId: 'rv-1',
          componentDefinitionId: 'sustaining-pilot',
          componentType: VisualComponentType.pilotValve,
          compartment: VisualCompartment.publicNetwork,
          sequence: 1,
          presenceAnswer: PresenceAnswer.installed,
          visualCondition: VisualComponentCondition.good,
          specificData: data,
          explicitlyConfirmed: true,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
    expect(
      VisualComponentRules.validate(
        pilot(const VisualComponentSpecificData()),
        hasValidPhoto: false,
      ).map((issue) => issue.code),
      contains('pilotConnected'),
    );
    expect(
      VisualComponentRules.validate(
        pilot(const VisualComponentSpecificData(pilotConnected: false)),
        hasValidPhoto: false,
      ).map((issue) => issue.code),
      isNot(contains('pilotConnected')),
    );
  });

  test('all RV capture paths use binary question without reason or photo', () {
    final renderer = File(
      'lib/features/checklist/presentation/dynamic_checklist_renderer.dart',
    ).readAsStringSync();
    final visual = File(
      'lib/features/visual_report/presentation/steps/visual_components_list_step_page.dart',
    ).readAsStringSync();
    final functional = File(
      'lib/features/functional/functional_inspection_page.dart',
    ).readAsStringSync();
    expect(renderer, contains('¿El piloto está conectado?'));
    expect(visual, contains('¿El piloto está conectado?'));
    expect(renderer, isNot(contains('pilotConnectionReason')));
    expect(renderer, isNot(contains('pilotConnectionPhoto')));
    expect(functional, isNot(contains('pilotConnected')));
  });
}
