import 'package:flutter_test/flutter_test.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_hydrant_configuration.dart';

void main() {
  group('configuraciones tipadas del REPORTE VISUAL', () {
    for (final entry in const {
      VisualHydrantType.a1: 21,
      VisualHydrantType.a2: 25,
      VisualHydrantType.a3: 29,
      VisualHydrantType.a4: 29,
    }.entries) {
      test('${entry.key.name} genera ${entry.value} componentes', () {
        final value = VisualHydrantConfigurationFactory.standard(
          entry.key,
          inspectionId: 'rv-1',
        );
        expect(value.components, hasLength(entry.value));
        expect(
          value.components.where(
            (item) => item.compartment == VisualCompartment.publicNetwork,
          ),
          hasLength(10),
        );
        expect(
          value.components.where(
            (item) => item.compartment == VisualCompartment.privateNetwork,
          ),
          hasLength(7),
        );
      });
    }

    test('A4 crea tres salidas con diámetro de 4 pulgadas', () {
      final value = VisualHydrantConfigurationFactory.standard(
        VisualHydrantType.a4,
        inspectionId: 'rv-a4',
      );
      expect(value.outlets, hasLength(3));
      expect(
        value.outlets.every((item) => item.expectedDiameter == '4 pulgadas'),
        isTrue,
      );
    });

    test('A5 calcula el total desde su definición serializada', () {
      final base = VisualHydrantConfigurationFactory.standard(
        VisualHydrantType.a5Custom,
        inspectionId: 'rv-a5',
      );
      final json = base.toJson();
      json['components'] = [
        ...json['components'] as List,
        {
          'id': 'custom-1',
          'type': VisualComponentType.other.name,
          'name': 'Elemento especial',
          'shortLabel': 'ESP',
          'compartment': VisualCompartment.privateNetwork.name,
          'catalogued': false,
        },
      ];
      final restored = VisualHydrantConfiguration.fromJson(json);
      expect(restored.components, hasLength(18));
      expect(restored.components.last.catalogued, isFalse);
    });
  });
}
