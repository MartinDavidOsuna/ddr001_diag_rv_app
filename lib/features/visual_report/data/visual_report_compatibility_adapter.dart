import 'package:uuid/uuid.dart';
import '../../../domain/enums/app_enums.dart';
import '../../../domain/inspections/visual_inspection.dart';
import '../domain/visual_component_models.dart';
import '../domain/visual_hydrant_configuration.dart';

class VisualReportCompatibilityAdapter {
  const VisualReportCompatibilityAdapter();

  VisualInspection project(VisualInspection source) {
    // Los reportes finalizados históricos pueden recibir una proyección en
    // memoria para mostrarse, pero conservan paso y versión. El repositorio no
    // la persiste al abrirlos.
    final readOnlyLegacy = source.status == InspectionStatus.completed;
    final upgraded = source.visualFlowVersion >= 2 || readOnlyLegacy
        ? source
        : source.copyWith(
            visualFlowVersion: 2,
            currentStep: _mapLegacyStep(source.currentStep),
            updatedAt: source.updatedAt,
          );
    if (upgraded.hydrantConfiguration != null &&
        upgraded.componentInspections.isNotEmpty) {
      return upgraded;
    }
    final configuration=upgraded.hydrantConfiguration ?? VisualHydrantConfigurationFactory.standard(VisualHydrantType.a1,inspectionId:upgraded.id);
    final now=upgraded.updatedAt;
    final components=[for(var index=0;index<configuration.components.length;index++) if (configuration.components[index].type != VisualComponentType.flowMeter) _legacyComponent(upgraded,configuration.components[index],index,now)];
    return upgraded.copyWith(hydrantConfiguration:configuration,componentInspections:components,outletInspections:configuration.outlets,updatedAt:source.updatedAt);
  }

  int _mapLegacyStep(int step) => switch (step) {
    6 => 7,
    7 => 8,
    8 => 9,
    _ => step.clamp(1, 9),
  };

  VisualComponentInspection _legacyComponent(VisualInspection source,VisualComponentDefinition definition,int sequence,DateTime now){
    PresenceAnswer? presence; VisualComponentCondition? condition;
    if(definition.type==VisualComponentType.flowMeter){
      presence=source.flowMeter.exists==null?null:source.flowMeter.exists!?PresenceAnswer.installed:PresenceAnswer.notInstalled;
      condition=_legacyCondition(source.flowMeter.condition);
    }else if(definition.type==VisualComponentType.regulatingValve){
      presence=source.pressureValve.exists==null?null:source.pressureValve.exists!?PresenceAnswer.installed:PresenceAnswer.notInstalled;
      condition=_legacyCondition(source.pressureValve.condition);
    }
    return VisualComponentInspection(
      id:const Uuid().v5(Namespace.url.value,'ddr001-visual-component:${source.id}:${definition.id}'),
      inspectionId:source.id,componentDefinitionId:definition.id,componentType:definition.type,compartment:definition.compartment,outletId:definition.outletNumber==null?null:'outlet-${definition.outletNumber}',sequence:sequence,presenceAnswer:presence,visualCondition:condition,reviewStatus:ComponentReviewStatus.pending,legacyRequiresConfirmation:true,createdAt:source.createdAt,updatedAt:now,
    );
  }

  VisualComponentCondition? _legacyCondition(PhysicalCondition? value)=>switch(value){PhysicalCondition.good=>VisualComponentCondition.good,PhysicalCondition.fair=>VisualComponentCondition.minorFinding,PhysicalCondition.bad=>VisualComponentCondition.majorFinding,PhysicalCondition.critical=>VisualComponentCondition.critical,PhysicalCondition.unknown=>VisualComponentCondition.notVerifiable,null=>null};
}
