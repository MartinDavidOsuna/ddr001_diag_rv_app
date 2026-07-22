import 'visual_component_models.dart';
import 'visual_hydrant_configuration.dart';

enum VisualSequenceItemKind { component, canonicalFlowMeter }

class VisualComponentSequenceItem {
  const VisualComponentSequenceItem.component({
    required this.definition,
    this.outlet,
  }) : kind = VisualSequenceItemKind.component;

  const VisualComponentSequenceItem.flowMeter()
      : kind = VisualSequenceItemKind.canonicalFlowMeter,
        definition = null,
        outlet = null;

  final VisualSequenceItemKind kind;
  final VisualComponentDefinition? definition;
  final VisualOutletInspection? outlet;

  String get id => kind == VisualSequenceItemKind.canonicalFlowMeter
      ? 'canonical-flow-meter'
      : definition!.id;
  String get name => kind == VisualSequenceItemKind.canonicalFlowMeter
      ? 'Medidor de caudal'
      : definition!.name;
}

abstract final class VisualComponentSequence {
  static List<VisualComponentSequenceItem> publicNetwork(
    VisualHydrantConfiguration configuration,
  ) {
    final definitions = configuration.components
        .where((item) => item.compartment == VisualCompartment.publicNetwork)
        .toList();
    final result = <VisualComponentSequenceItem>[];
    for (final definition in definitions) {
      if (definition.type == VisualComponentType.flowMeter) {
        result.add(const VisualComponentSequenceItem.flowMeter());
      } else {
        result.add(VisualComponentSequenceItem.component(
          definition: definition,
        ));
      }
    }
    return result;
  }

  static List<VisualComponentSequenceItem> privateNetwork(
    VisualHydrantConfiguration configuration,
  ) {
    final result = <VisualComponentSequenceItem>[
      for (final definition in configuration.components.where(
        (item) => item.compartment == VisualCompartment.privateNetwork,
      ))
        VisualComponentSequenceItem.component(definition: definition),
    ];
    for (final outlet in configuration.outlets
        .where((item) => item.active)
        .toList()
      ..sort((a, b) => a.outletNumber.compareTo(b.outletNumber))) {
      final outletComponents = configuration.components
          .where((item) =>
              item.compartment == VisualCompartment.outlet &&
              item.outletNumber == outlet.outletNumber)
          .toList();
      result.addAll([
        for (final definition in outletComponents)
          VisualComponentSequenceItem.component(
            definition: definition,
            outlet: outlet,
          ),
      ]);
    }
    return result;
  }
}
