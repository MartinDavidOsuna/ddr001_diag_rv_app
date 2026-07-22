import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_sequence.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_hydrant_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secuencia pública contiene diez elementos y un medidor canónico', () {
    final configuration = VisualHydrantConfigurationFactory.standard(
      VisualHydrantType.a1,
      inspectionId: 'rv',
    );
    final sequence = VisualComponentSequence.publicNetwork(configuration);
    expect(sequence, hasLength(10));
    expect(
      sequence.where((item) =>
          item.kind == VisualSequenceItemKind.canonicalFlowMeter),
      hasLength(1),
    );
  });

  for (final entry in const {
    VisualHydrantType.a1: 11,
    VisualHydrantType.a2: 15,
    VisualHydrantType.a3: 19,
    VisualHydrantType.a4: 19,
  }.entries) {
    test('${entry.key.name} produce ${entry.value} elementos privados', () {
      final configuration = VisualHydrantConfigurationFactory.standard(
        entry.key,
        inspectionId: 'rv-${entry.key.name}',
      );
      expect(
        VisualComponentSequence.privateNetwork(configuration),
        hasLength(entry.value),
      );
    });
  }

  test('A5 deriva la secuencia únicamente de su configuración', () {
    final source = VisualHydrantConfigurationFactory.standard(
      VisualHydrantType.a2,
      inspectionId: 'rv-a5',
    ).toJson()
      ..['type'] = VisualHydrantType.a5Custom.name
      ..['expectedType'] = VisualHydrantType.a5Custom.name
      ..['observedType'] = VisualHydrantType.a5Custom.name;
    final configuration = VisualHydrantConfiguration.fromJson(source);
    expect(
      VisualComponentSequence.privateNetwork(configuration),
      hasLength(15),
    );
  });
}
