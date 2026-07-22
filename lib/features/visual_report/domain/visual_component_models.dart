import 'package:uuid/uuid.dart';

enum VisualHydrantType { a1, a2, a3, a4, a5Custom }

enum VisualCompartment { publicNetwork, privateNetwork, outlet }

enum VisualComponentType {
  serviceValve,
  flowMeter,
  regulatingValve,
  solenoid,
  pilotValve,
  pressureGauge,
  airValve,
  venturi,
  victaulicGroup,
  filter,
  filterAssembly,
  filterWashValve,
  sectioningValve,
  outletConnection,
  pipe,
  other,
}

enum PresenceAnswer { installed, notInstalled, cannotConfirm, notApplicable }

enum VisualComponentCondition {
  good,
  minorFinding,
  majorFinding,
  critical,
  notVerifiable,
  notApplicable,
}

enum ComponentReviewStatus {
  pending,
  inProgress,
  reviewed,
  needsAttention,
  blocked,
}

enum ObservedCondition {
  noVisibleDamage,
  corrosion,
  leakage,
  impactOrDeformation,
  loose,
  incomplete,
  obstruction,
  manipulation,
  unidentified,
  moisture,
  brokenCable,
  damagedConnector,
  missingProtection,
  other,
}

extension VisualHydrantTypeLabel on VisualHydrantType {
  String get label => this == VisualHydrantType.a5Custom
      ? 'A5 Custom'
      : name.toUpperCase();
}

extension VisualCompartmentLabel on VisualCompartment {
  String get label => switch (this) {
    VisualCompartment.publicNetwork => 'Red pública',
    VisualCompartment.privateNetwork => 'Red privada',
    VisualCompartment.outlet => 'Salidas',
  };
}

extension PresenceAnswerLabel on PresenceAnswer {
  String get label => switch (this) {
    PresenceAnswer.installed => 'Sí',
    PresenceAnswer.notInstalled => 'No',
    PresenceAnswer.cannotConfirm => 'No se puede confirmar',
    PresenceAnswer.notApplicable => 'No aplica',
  };
}

extension VisualComponentConditionLabel on VisualComponentCondition {
  String get label => switch (this) {
    VisualComponentCondition.good => 'Bueno',
    VisualComponentCondition.minorFinding => 'Hallazgo menor',
    VisualComponentCondition.majorFinding => 'Hallazgo importante',
    VisualComponentCondition.critical => 'Crítico',
    VisualComponentCondition.notVerifiable => 'No verificable',
    VisualComponentCondition.notApplicable => 'No aplica',
  };
}

extension ObservedConditionLabel on ObservedCondition {
  String get label => switch (this) {
    ObservedCondition.noVisibleDamage => 'Sin daño visible',
    ObservedCondition.corrosion => 'Corrosión',
    ObservedCondition.leakage => 'Fuga',
    ObservedCondition.impactOrDeformation => 'Impacto o deformación',
    ObservedCondition.loose => 'Suelto',
    ObservedCondition.incomplete => 'Incompleto',
    ObservedCondition.obstruction => 'Obstrucción',
    ObservedCondition.manipulation => 'Manipulación',
    ObservedCondition.unidentified => 'No identificado',
    ObservedCondition.moisture => 'Humedad',
    ObservedCondition.brokenCable => 'Cable roto',
    ObservedCondition.damagedConnector => 'Conector dañado',
    ObservedCondition.missingProtection => 'Protección faltante',
    ObservedCondition.other => 'Otro',
  };
}

class VisualComponentDefinition {
  const VisualComponentDefinition({
    required this.id,
    required this.type,
    required this.name,
    required this.shortLabel,
    required this.compartment,
    this.outletNumber,
    this.expectedDiameter,
    this.quickReviewEligible = true,
    this.catalogued = true,
  });
  final String id, name, shortLabel;
  final VisualComponentType type;
  final VisualCompartment compartment;
  final int? outletNumber;
  final String? expectedDiameter;
  final bool quickReviewEligible, catalogued;
}

class VisualComponentSpecificData {
  const VisualComponentSpecificData({
    this.visibleType,
    this.visibleDiameter,
    this.visibleMaterial,
    this.bodyCondition,
    this.mechanismCondition,
    this.fixingCondition,
    this.apparentPosition,
    this.accessibility,
    this.coverCondition,
    this.connectionsCondition,
    this.tubingCondition,
    this.identificationLegible,
    this.solenoidPresent,
    this.solenoidCount,
    this.solenoidAbsenceReason,
    this.faceLegible,
    this.glassIntact,
    this.needleVisible,
    this.visibleRange,
    this.visibleUnit,
    this.orientation,
    this.observedReading,
    this.readingUnit,
    this.directionArrowVisible,
    this.pressureTapsCondition,
    this.dischargeCondition,
    this.maintenanceAccess,
    this.apparentlyPresent,
    this.internalVisibility,
    this.outletConnectionCondition,
    this.protectionCondition,
    this.connectionThreadCondition,
    this.otherDescription,
  });
  final String? visibleType,
      visibleDiameter,
      visibleMaterial,
      bodyCondition,
      mechanismCondition,
      fixingCondition,
      apparentPosition,
      accessibility,
      coverCondition,
      connectionsCondition,
      tubingCondition,
      solenoidAbsenceReason,
      visibleRange,
      visibleUnit,
      orientation,
      observedReading,
      readingUnit,
      pressureTapsCondition,
      dischargeCondition,
      maintenanceAccess,
      internalVisibility,
      outletConnectionCondition,
      protectionCondition,
      connectionThreadCondition,
      otherDescription;
  final bool? identificationLegible,
      solenoidPresent,
      faceLegible,
      glassIntact,
      needleVisible,
      directionArrowVisible,
      apparentlyPresent;
  final int? solenoidCount;

  VisualComponentSpecificData copyWith({
    String? visibleMaterial,
    bool? faceLegible,
    String? visibleRange,
    String? visibleUnit,
    String? internalVisibility,
  }) => VisualComponentSpecificData(
    visibleType: visibleType,
    visibleDiameter: visibleDiameter,
    visibleMaterial: visibleMaterial ?? this.visibleMaterial,
    bodyCondition: bodyCondition,
    mechanismCondition: mechanismCondition,
    fixingCondition: fixingCondition,
    apparentPosition: apparentPosition,
    accessibility: accessibility,
    coverCondition: coverCondition,
    connectionsCondition: connectionsCondition,
    tubingCondition: tubingCondition,
    identificationLegible: identificationLegible,
    solenoidPresent: solenoidPresent,
    solenoidCount: solenoidCount,
    solenoidAbsenceReason: solenoidAbsenceReason,
    faceLegible: faceLegible ?? this.faceLegible,
    glassIntact: glassIntact,
    needleVisible: needleVisible,
    visibleRange: visibleRange ?? this.visibleRange,
    visibleUnit: visibleUnit ?? this.visibleUnit,
    orientation: orientation,
    observedReading: observedReading,
    readingUnit: readingUnit,
    directionArrowVisible: directionArrowVisible,
    pressureTapsCondition: pressureTapsCondition,
    dischargeCondition: dischargeCondition,
    maintenanceAccess: maintenanceAccess,
    apparentlyPresent: apparentlyPresent,
    internalVisibility: internalVisibility ?? this.internalVisibility,
    outletConnectionCondition: outletConnectionCondition,
    protectionCondition: protectionCondition,
    connectionThreadCondition: connectionThreadCondition,
    otherDescription: otherDescription,
  );

  Map<String, dynamic> toJson() => {
    'visibleType': visibleType,
    'visibleDiameter': visibleDiameter,
    'visibleMaterial': visibleMaterial,
    'bodyCondition': bodyCondition,
    'mechanismCondition': mechanismCondition,
    'fixingCondition': fixingCondition,
    'apparentPosition': apparentPosition,
    'accessibility': accessibility,
    'coverCondition': coverCondition,
    'connectionsCondition': connectionsCondition,
    'tubingCondition': tubingCondition,
    'identificationLegible': identificationLegible,
    'solenoidPresent': solenoidPresent,
    'solenoidCount': solenoidCount,
    'solenoidAbsenceReason': solenoidAbsenceReason,
    'faceLegible': faceLegible,
    'glassIntact': glassIntact,
    'needleVisible': needleVisible,
    'visibleRange': visibleRange,
    'visibleUnit': visibleUnit,
    'orientation': orientation,
    'observedReading': observedReading,
    'readingUnit': readingUnit,
    'directionArrowVisible': directionArrowVisible,
    'pressureTapsCondition': pressureTapsCondition,
    'dischargeCondition': dischargeCondition,
    'maintenanceAccess': maintenanceAccess,
    'apparentlyPresent': apparentlyPresent,
    'internalVisibility': internalVisibility,
    'outletConnectionCondition': outletConnectionCondition,
    'protectionCondition': protectionCondition,
    'connectionThreadCondition': connectionThreadCondition,
    'otherDescription': otherDescription,
  };

  factory VisualComponentSpecificData.fromJson(Map<String, dynamic> j) =>
      VisualComponentSpecificData(
        visibleType: j['visibleType'] as String?,
        visibleDiameter: j['visibleDiameter'] as String?,
        visibleMaterial: j['visibleMaterial'] as String?,
        bodyCondition: j['bodyCondition'] as String?,
        mechanismCondition: j['mechanismCondition'] as String?,
        fixingCondition: j['fixingCondition'] as String?,
        apparentPosition: j['apparentPosition'] as String?,
        accessibility: j['accessibility'] as String?,
        coverCondition: j['coverCondition'] as String?,
        connectionsCondition: j['connectionsCondition'] as String?,
        tubingCondition: j['tubingCondition'] as String?,
        identificationLegible: j['identificationLegible'] as bool?,
        solenoidPresent: j['solenoidPresent'] as bool?,
        solenoidCount: j['solenoidCount'] as int?,
        solenoidAbsenceReason: j['solenoidAbsenceReason'] as String?,
        faceLegible: j['faceLegible'] as bool?,
        glassIntact: j['glassIntact'] as bool?,
        needleVisible: j['needleVisible'] as bool?,
        visibleRange: j['visibleRange'] as String?,
        visibleUnit: j['visibleUnit'] as String?,
        orientation: j['orientation'] as String?,
        observedReading: j['observedReading'] as String?,
        readingUnit: j['readingUnit'] as String?,
        directionArrowVisible: j['directionArrowVisible'] as bool?,
        pressureTapsCondition: j['pressureTapsCondition'] as String?,
        dischargeCondition: j['dischargeCondition'] as String?,
        maintenanceAccess: j['maintenanceAccess'] as String?,
        apparentlyPresent: j['apparentlyPresent'] as bool?,
        internalVisibility: j['internalVisibility'] as String?,
        outletConnectionCondition: j['outletConnectionCondition'] as String?,
        protectionCondition: j['protectionCondition'] as String?,
        connectionThreadCondition: j['connectionThreadCondition'] as String?,
        otherDescription: j['otherDescription'] as String?,
      );
}

class VisualComponentInspection {
  const VisualComponentInspection({
    required this.id,
    required this.inspectionId,
    required this.componentDefinitionId,
    required this.componentType,
    required this.compartment,
    this.outletId,
    required this.sequence,
    this.expected = true,
    this.presenceAnswer,
    this.visualCondition,
    this.observedConditions = const {},
    this.reviewStatus = ComponentReviewStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.quickReviewApplied = false,
    this.suggestedDefaultsApplied = false,
    this.explicitlyConfirmed = false,
    this.comment = '',
    this.otherConditionDescription = '',
    this.photoIds = const [],
    this.specificData = const VisualComponentSpecificData(),
    required this.createdAt,
    required this.updatedAt,
    this.retiredAt,
    this.configurationDifference = false,
    this.legacyRequiresConfirmation = false,
    this.schemaVersion = 3,
    this.unknownFields = const {},
  });
  final String id, inspectionId, componentDefinitionId, comment;
  final String otherConditionDescription;
  final VisualComponentType componentType;
  final VisualCompartment compartment;
  final String? outletId, reviewedBy;
  final int sequence, schemaVersion;
  final bool expected,
      quickReviewApplied,
      suggestedDefaultsApplied,
      explicitlyConfirmed,
      configurationDifference,
      legacyRequiresConfirmation;
  final PresenceAnswer? presenceAnswer;
  final VisualComponentCondition? visualCondition;
  final Set<ObservedCondition> observedConditions;
  final ComponentReviewStatus reviewStatus;
  final DateTime? reviewedAt, retiredAt;
  final List<String> photoIds;
  final VisualComponentSpecificData specificData;
  final DateTime createdAt, updatedAt;
  final Map<String, dynamic> unknownFields;
  bool get active => retiredAt == null;
  bool get isReviewed =>
      explicitlyConfirmed &&
      const {
        ComponentReviewStatus.reviewed,
        ComponentReviewStatus.needsAttention,
      }.contains(reviewStatus);
  bool get hasFinding => const {
    VisualComponentCondition.minorFinding,
    VisualComponentCondition.majorFinding,
    VisualComponentCondition.critical,
  }.contains(visualCondition);
  String get conditionLabel => visualCondition?.label ?? 'Pendiente';
  String get summaryLabel =>
      '$conditionLabel · ${photoIds.length} ${photoIds.length == 1 ? 'foto' : 'fotos'}'
      '${configurationDifference ? ' · Diferencia' : ''}';

  VisualComponentInspection copyWith({
    PresenceAnswer? presenceAnswer,
    VisualComponentCondition? visualCondition,
    Set<ObservedCondition>? observedConditions,
    ComponentReviewStatus? reviewStatus,
    String? reviewedBy,
    DateTime? reviewedAt,
    bool? quickReviewApplied,
    bool? suggestedDefaultsApplied,
    bool? explicitlyConfirmed,
    String? comment,
    String? otherConditionDescription,
    List<String>? photoIds,
    VisualComponentSpecificData? specificData,
    DateTime? updatedAt,
    bool? configurationDifference,
    bool clearVisualCondition = false,
    bool clearReviewedAt = false,
    bool clearReviewedBy = false,
  }) => VisualComponentInspection(
    id: id,
    inspectionId: inspectionId,
    componentDefinitionId: componentDefinitionId,
    componentType: componentType,
    compartment: compartment,
    outletId: outletId,
    sequence: sequence,
    expected: expected,
    presenceAnswer: presenceAnswer ?? this.presenceAnswer,
    visualCondition:
        clearVisualCondition ? null : visualCondition ?? this.visualCondition,
    observedConditions: observedConditions ?? this.observedConditions,
    reviewStatus: reviewStatus ?? this.reviewStatus,
    reviewedBy: clearReviewedBy ? null : reviewedBy ?? this.reviewedBy,
    reviewedAt: clearReviewedAt ? null : reviewedAt ?? this.reviewedAt,
    quickReviewApplied: quickReviewApplied ?? this.quickReviewApplied,
    suggestedDefaultsApplied:
        suggestedDefaultsApplied ?? this.suggestedDefaultsApplied,
    explicitlyConfirmed: explicitlyConfirmed ?? this.explicitlyConfirmed,
    comment: comment ?? this.comment,
    otherConditionDescription:
        otherConditionDescription ?? this.otherConditionDescription,
    photoIds: photoIds ?? this.photoIds,
    specificData: specificData ?? this.specificData,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    retiredAt: retiredAt,
    configurationDifference:
        configurationDifference ?? this.configurationDifference,
    legacyRequiresConfirmation: legacyRequiresConfirmation,
    schemaVersion: schemaVersion,
    unknownFields: unknownFields,
  );

  Map<String, dynamic> toJson() => {
    ...unknownFields,
    'id': id,
    'inspectionId': inspectionId,
    'componentDefinitionId': componentDefinitionId,
    'componentType': componentType.name,
    'compartment': compartment.name,
    'outletId': outletId,
    'sequence': sequence,
    'expected': expected,
    'presenceAnswer': presenceAnswer?.name,
    'visualCondition': visualCondition?.name,
    'observedConditions': observedConditions.map((v) => v.name).toList(),
    'reviewStatus': reviewStatus.name,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
    'quickReviewApplied': quickReviewApplied,
    'suggestedDefaultsApplied': suggestedDefaultsApplied,
    'explicitlyConfirmed': explicitlyConfirmed,
    'comment': comment,
    'otherConditionDescription': otherConditionDescription,
    'photoIds': photoIds,
    'specificData': specificData.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'retiredAt': retiredAt?.toUtc().toIso8601String(),
    'configurationDifference': configurationDifference,
    'legacyRequiresConfirmation': legacyRequiresConfirmation,
    'schemaVersion': schemaVersion,
  };

  factory VisualComponentInspection.fromJson(Map<String, dynamic> j) {
    const known = {
      'id','inspectionId','componentDefinitionId','componentType','compartment',
      'outletId','sequence','expected','presenceAnswer','visualCondition',
      'observedConditions','reviewStatus','reviewedBy','reviewedAt',
      'quickReviewApplied','suggestedDefaultsApplied','explicitlyConfirmed',
      'comment','otherConditionDescription','photoIds',
      'specificData','createdAt','updatedAt','retiredAt',
      'configurationDifference','legacyRequiresConfirmation','schemaVersion',
    };
    return VisualComponentInspection(
      id: j['id'] as String,
      inspectionId: j['inspectionId'] as String,
      componentDefinitionId: j['componentDefinitionId'] as String,
      componentType: _enum(VisualComponentType.values, j['componentType'], VisualComponentType.other),
      compartment: _enum(VisualCompartment.values, j['compartment'], VisualCompartment.privateNetwork),
      outletId: j['outletId'] as String?,
      sequence: j['sequence'] as int? ?? 0,
      expected: j['expected'] as bool? ?? true,
      presenceAnswer: _nullableEnum(PresenceAnswer.values, j['presenceAnswer']),
      visualCondition: _nullableEnum(VisualComponentCondition.values, j['visualCondition']),
      observedConditions: (j['observedConditions'] as List? ?? const [])
          .map((v) => _nullableEnum(ObservedCondition.values, v))
          .whereType<ObservedCondition>().toSet(),
      reviewStatus: _enum(ComponentReviewStatus.values, j['reviewStatus'], ComponentReviewStatus.pending),
      reviewedBy: j['reviewedBy'] as String?,
      reviewedAt: DateTime.tryParse(j['reviewedAt'] as String? ?? '')?.toUtc(),
      quickReviewApplied: j['quickReviewApplied'] as bool? ?? false,
      suggestedDefaultsApplied:
          j['suggestedDefaultsApplied'] as bool? ?? false,
      explicitlyConfirmed: j['explicitlyConfirmed'] as bool? ?? false,
      comment: j['comment'] as String? ?? '',
      otherConditionDescription: j['otherConditionDescription'] as String? ?? '',
      photoIds: (j['photoIds'] as List? ?? const []).map((v) => '$v').toList(),
      specificData: VisualComponentSpecificData.fromJson(Map<String,dynamic>.from(j['specificData'] as Map? ?? const {})),
      createdAt: _date(j['createdAt']), updatedAt: _date(j['updatedAt']),
      retiredAt: DateTime.tryParse(j['retiredAt'] as String? ?? '')?.toUtc(),
      configurationDifference: j['configurationDifference'] as bool? ?? false,
      legacyRequiresConfirmation: j['legacyRequiresConfirmation'] as bool? ?? false,
      schemaVersion: j['schemaVersion'] as int? ?? 1,
      unknownFields: {for(final e in j.entries) if(!known.contains(e.key)) e.key:e.value},
    );
  }
}

class VisualOutletInspection {
  const VisualOutletInspection({required this.id, required this.inspectionId, required this.outletNumber, required this.expectedDiameter, this.observedDiameter, required this.componentIds, this.active = true, this.photoIds = const [], this.schemaVersion = 2});
  final String id, inspectionId, expectedDiameter;
  final String? observedDiameter;
  final int outletNumber, schemaVersion;
  final List<String> componentIds, photoIds;
  final bool active;
  Map<String,dynamic> toJson()=>{'id':id,'inspectionId':inspectionId,'outletNumber':outletNumber,'expectedDiameter':expectedDiameter,'observedDiameter':observedDiameter,'componentIds':componentIds,'active':active,'photoIds':photoIds,'schemaVersion':schemaVersion};
  factory VisualOutletInspection.fromJson(Map<String,dynamic> j)=>VisualOutletInspection(id:j['id'] as String,inspectionId:j['inspectionId'] as String,outletNumber:j['outletNumber'] as int,expectedDiameter:j['expectedDiameter'] as String? ?? '',observedDiameter:j['observedDiameter'] as String?,componentIds:(j['componentIds'] as List? ?? const []).cast<String>(),active:j['active'] as bool? ?? true,photoIds:(j['photoIds'] as List? ?? const []).cast<String>(),schemaVersion:j['schemaVersion'] as int? ?? 1);
}

class VisualJointInspection {
  const VisualJointInspection({required this.id, required this.number, this.location='', this.material='', this.condition, this.observedConditions=const {}, this.photoIds=const [], this.comments=''});
  final String id, location, material, comments; final int number;
  final VisualComponentCondition? condition; final Set<ObservedCondition> observedConditions; final List<String> photoIds;
  Map<String,dynamic> toJson()=>{'id':id,'number':number,'location':location,'material':material,'condition':condition?.name,'observedConditions':observedConditions.map((e)=>e.name).toList(),'photoIds':photoIds,'comments':comments};
  factory VisualJointInspection.fromJson(Map<String,dynamic> j)=>VisualJointInspection(id:j['id'] as String,number:j['number'] as int? ?? 0,location:j['location'] as String? ?? '',material:j['material'] as String? ?? '',condition:_nullableEnum(VisualComponentCondition.values,j['condition']),observedConditions:(j['observedConditions'] as List? ?? const []).map((e)=>_nullableEnum(ObservedCondition.values,e)).whereType<ObservedCondition>().toSet(),photoIds:(j['photoIds'] as List? ?? const []).cast<String>(),comments:j['comments'] as String? ?? '');
}

class VisualVictaulicGroupInspection {
  const VisualVictaulicGroupInspection({required this.componentInspectionId,this.quantity=0,this.material='',this.commonCondition,this.sameConditionForAll=true,this.individualJoints=const [],this.comments=''});
  final String componentInspectionId,material,comments; final int quantity; final VisualComponentCondition? commonCondition; final bool sameConditionForAll; final List<VisualJointInspection> individualJoints;
  VisualVictaulicGroupInspection copyWith({int? quantity,String? material,VisualComponentCondition? commonCondition,bool? sameConditionForAll,List<VisualJointInspection>? individualJoints,String? comments})=>VisualVictaulicGroupInspection(componentInspectionId:componentInspectionId,quantity:quantity??this.quantity,material:material??this.material,commonCondition:commonCondition??this.commonCondition,sameConditionForAll:sameConditionForAll??this.sameConditionForAll,individualJoints:individualJoints??this.individualJoints,comments:comments??this.comments);
  VisualVictaulicGroupInspection withQuantity(int next){
    final safe=next.clamp(0,50);
    return copyWith(quantity:safe,individualJoints:[for(var index=0;index<safe;index++) if(index<individualJoints.length) individualJoints[index] else VisualJointInspection(id:const Uuid().v4(),number:index+1)]);
  }
  Map<String,dynamic> toJson()=>{'componentInspectionId':componentInspectionId,'quantity':quantity,'material':material,'commonCondition':commonCondition?.name,'sameConditionForAll':sameConditionForAll,'individualJoints':individualJoints.map((e)=>e.toJson()).toList(),'comments':comments};
  factory VisualVictaulicGroupInspection.fromJson(Map<String,dynamic> j)=>VisualVictaulicGroupInspection(componentInspectionId:j['componentInspectionId'] as String,quantity:j['quantity'] as int? ?? 0,material:j['material'] as String? ?? '',commonCondition:_nullableEnum(VisualComponentCondition.values,j['commonCondition']),sameConditionForAll:j['sameConditionForAll'] as bool? ?? true,individualJoints:(j['individualJoints'] as List? ?? const []).map((e)=>VisualJointInspection.fromJson(Map<String,dynamic>.from(e as Map))).toList(),comments:j['comments'] as String? ?? '');
}

T _enum<T extends Enum>(List<T> values,Object? raw,T fallback)=>values.where((e)=>e.name==raw).firstOrNull ?? fallback;
T? _nullableEnum<T extends Enum>(List<T> values,Object? raw)=>values.where((e)=>e.name==raw).firstOrNull;
DateTime _date(Object? raw)=>DateTime.tryParse(raw as String? ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0,isUtc:true);
