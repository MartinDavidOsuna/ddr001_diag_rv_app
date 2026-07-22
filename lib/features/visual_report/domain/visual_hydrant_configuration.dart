import 'package:uuid/uuid.dart';
import 'visual_component_models.dart';

class VisualHydrantConfiguration {
  const VisualHydrantConfiguration({required this.type,required this.expectedType,required this.observedType,this.hasConfigurationDifferences=false,this.differenceReason='',required this.components,required this.outlets,this.schemaVersion=2});
  final VisualHydrantType type,expectedType,observedType; final bool hasConfigurationDifferences; final String differenceReason; final List<VisualComponentDefinition> components; final List<VisualOutletInspection> outlets; final int schemaVersion;
  int get expectedComponentCount=>components.length;
  Map<String,dynamic> toJson()=>{'type':type.name,'expectedType':expectedType.name,'observedType':observedType.name,'hasConfigurationDifferences':hasConfigurationDifferences,'differenceReason':differenceReason,'components':components.map((e)=>{'id':e.id,'type':e.type.name,'name':e.name,'shortLabel':e.shortLabel,'compartment':e.compartment.name,'outletNumber':e.outletNumber,'expectedDiameter':e.expectedDiameter,'quickReviewEligible':e.quickReviewEligible,'catalogued':e.catalogued}).toList(),'outlets':outlets.map((e)=>e.toJson()).toList(),'schemaVersion':schemaVersion};
  factory VisualHydrantConfiguration.fromJson(Map<String,dynamic> j)=>VisualHydrantConfiguration(type:_value(VisualHydrantType.values,j['type'],VisualHydrantType.a1),expectedType:_value(VisualHydrantType.values,j['expectedType'],VisualHydrantType.a1),observedType:_value(VisualHydrantType.values,j['observedType'],VisualHydrantType.a1),hasConfigurationDifferences:j['hasConfigurationDifferences'] as bool? ?? false,differenceReason:j['differenceReason'] as String? ?? '',components:(j['components'] as List? ?? const []).map((raw){final e=Map<String,dynamic>.from(raw as Map);return VisualComponentDefinition(id:e['id'] as String,type:_value(VisualComponentType.values,e['type'],VisualComponentType.other),name:e['name'] as String? ?? '',shortLabel:e['shortLabel'] as String? ?? '',compartment:_value(VisualCompartment.values,e['compartment'],VisualCompartment.privateNetwork),outletNumber:e['outletNumber'] as int?,expectedDiameter:e['expectedDiameter'] as String?,quickReviewEligible:e['quickReviewEligible'] as bool? ?? true,catalogued:e['catalogued'] as bool? ?? true);}).toList(),outlets:(j['outlets'] as List? ?? const []).map((e)=>VisualOutletInspection.fromJson(Map<String,dynamic>.from(e as Map))).toList(),schemaVersion:j['schemaVersion'] as int? ?? 1);
}

T _value<T extends Enum>(List<T> values,Object? raw,T fallback)=>values.where((e)=>e.name==raw).firstOrNull ?? fallback;

abstract final class VisualHydrantConfigurationFactory {
  static const _public=<({String id,VisualComponentType type,String name,String short,bool quick})>[
    (id:'public-service-valve-1',type:VisualComponentType.serviceValve,name:'Válvula de servicio 1',short:'VS1',quick:true),
    (id:'flow-meter',type:VisualComponentType.flowMeter,name:'Medidor de caudal',short:'MED',quick:false),
    (id:'regulating-valve',type:VisualComponentType.regulatingValve,name:'Válvula sostenedora-reguladora',short:'VSR',quick:false),
    (id:'sustaining-pilot',type:VisualComponentType.pilotValve,name:'Válvula piloto sostenedora',short:'PS',quick:true),
    (id:'regulating-pilot',type:VisualComponentType.pilotValve,name:'Válvula piloto reguladora',short:'PR',quick:true),
    (id:'gauge-before-regulator',type:VisualComponentType.pressureGauge,name:'Manómetro antes de válvula sostenedora',short:'M1',quick:false),
    (id:'gauge-after-regulator',type:VisualComponentType.pressureGauge,name:'Manómetro después de válvula sostenedora',short:'M2',quick:false),
    (id:'air-valve',type:VisualComponentType.airValve,name:'Válvula de aire',short:'VA',quick:true),
    (id:'public-venturi-valve',type:VisualComponentType.venturi,name:'Válvula Venturi',short:'VV',quick:true),
    (id:'victaulic-group',type:VisualComponentType.victaulicGroup,name:'Grupo de juntas Victaulic',short:'JV',quick:false),
  ];
  static const _private=<({String id,VisualComponentType type,String name,String short,bool quick})>[
    (id:'private-service-valve-2',type:VisualComponentType.serviceValve,name:'Válvula de servicio 2',short:'VS2',quick:true),
    (id:'private-venturi',type:VisualComponentType.venturi,name:'Venturi',short:'VT',quick:true),
    (id:'gauge-before-filter',type:VisualComponentType.pressureGauge,name:'Manómetro antes del filtro',short:'M3',quick:false),
    (id:'gauge-after-filter',type:VisualComponentType.pressureGauge,name:'Manómetro después del filtro',short:'M4',quick:false),
    (id:'filter',type:VisualComponentType.filter,name:'Filtro',short:'FIL',quick:false),
    (id:'filter-assembly',type:VisualComponentType.filterAssembly,name:'Conjunto filtrante',short:'CF',quick:false),
    (id:'filter-wash-valve',type:VisualComponentType.filterWashValve,name:'Válvula de lavado del filtro',short:'VL',quick:true),
  ];

  static VisualHydrantConfiguration standard(VisualHydrantType type,{required String inspectionId}) {
    final count=switch(type){VisualHydrantType.a1=>1,VisualHydrantType.a2=>2,VisualHydrantType.a3||VisualHydrantType.a4=>3,VisualHydrantType.a5Custom=>0};
    final diameter=type==VisualHydrantType.a4?'4 pulgadas':'3 pulgadas';
    final definitions=<VisualComponentDefinition>[
      for(final c in _public) VisualComponentDefinition(id:c.id,type:c.type,name:c.name,shortLabel:c.short,compartment:VisualCompartment.publicNetwork,quickReviewEligible:c.quick),
      for(final c in _private) VisualComponentDefinition(id:c.id,type:c.type,name:c.name,shortLabel:c.short,compartment:VisualCompartment.privateNetwork,quickReviewEligible:c.quick),
    ];
    final outlets=<VisualOutletInspection>[];
    for(var number=1;number<=count;number++){
      final outletId='outlet-$number';
      final ids=<String>[];
      for(final item in [
        (VisualComponentType.sectioningValve,'Válvula de seccionamiento','VS'),
        (VisualComponentType.pilotValve,'Válvula piloto','VP'),
        (VisualComponentType.pressureGauge,'Manómetro de salida','MS'),
        (VisualComponentType.outletConnection,'Toma de salida','TS'),
      ]){
        final id='$outletId-${item.$1.name}'; ids.add(id);
        definitions.add(VisualComponentDefinition(id:id,type:item.$1,name:item.$2,shortLabel:'${item.$3}$number',compartment:VisualCompartment.outlet,outletNumber:number,expectedDiameter:diameter,quickReviewEligible:item.$1!=VisualComponentType.pressureGauge));
      }
      outlets.add(VisualOutletInspection(id:const Uuid().v4(),inspectionId:inspectionId,outletNumber:number,expectedDiameter:diameter,componentIds:ids));
    }
    return VisualHydrantConfiguration(type:type,expectedType:type,observedType:type,components:definitions,outlets:outlets);
  }
}
