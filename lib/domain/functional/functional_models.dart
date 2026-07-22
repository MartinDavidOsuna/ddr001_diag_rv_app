import '../enums/app_enums.dart';

enum FunctionalEligibilitySource {
  assignedBySupervisor,
  selectedInNewSurvey,
  requiredByVisualResult,
  urgentFieldInspection,
  technicalCampaign,
  manualAuthorization,
  demo,
}

enum FunctionalInspectionStatus {
  draft,
  ready,
  inProgress,
  paused,
  suspended,
  completed,
  cancelled,
  requiresRepeat,
  pendingReview,
  synced,
}

enum WorkSelection { visualOnly, functionalOnly, visualAndFunctional }

enum CalibrationStatus { valid, dueSoon, expired, unknown, notApplicable }

enum InstrumentIdentificationStatus {
  identified,
  notIdentifiable,
  unreadable,
  noPlate,
  notIdentified,
}

enum InstrumentLifecycleStatus { active, retired, unfit, logicallyDeleted }

enum MeasurementSource {
  manual,
  bluetooth,
  modbus,
  externalDevice,
  calculated,
  imported,
}

enum EvidenceRequirementStatus {
  pending,
  provided,
  notApplicable,
  notPerformed,
}

enum FunctionalOverallResult {
  approved,
  approvedWithObservations,
  partialOperation,
  requiresAdjustment,
  requiresRepair,
  requiresReplacement,
  incompleteTest,
  notEvaluable,
  suspended,
}

class FunctionalReportEligibility {
  const FunctionalReportEligibility({
    required this.hydrantId,
    required this.allowed,
    required this.source,
    required this.reason,
    required this.authorizedBy,
    this.authorizedRole = '',
    this.deviceId = '',
    required this.authorizedAt,
    this.pendingValidation = false,
    this.supervisorValidationRequired = false,
    this.visualReportRequired = false,
    this.visualReportId,
    this.restrictions = const [],
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });
  final String hydrantId, reason, authorizedBy, authorizedRole, deviceId;
  final bool allowed,
      pendingValidation,
      supervisorValidationRequired,
      visualReportRequired;
  final FunctionalEligibilitySource source;
  final DateTime authorizedAt, createdAt, updatedAt;
  final String? visualReportId;
  final List<String> restrictions;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'hydrantId': hydrantId,
    'allowed': allowed,
    'source': source.name,
    'reason': reason,
    'authorizedBy': authorizedBy,
    'authorizedRole': authorizedRole,
    'deviceId': deviceId,
    'authorizedAt': _dateToJson(authorizedAt),
    'pendingValidation': pendingValidation,
    'supervisorValidationRequired': supervisorValidationRequired,
    'visualReportRequired': visualReportRequired,
    'visualReportId': visualReportId,
    'restrictions': restrictions,
    'createdAt': _dateToJson(createdAt),
    'updatedAt': _dateToJson(updatedAt),
    'schemaVersion': schemaVersion,
  };
  factory FunctionalReportEligibility.fromJson(Map<String, dynamic> json) =>
      FunctionalReportEligibility(
        hydrantId: json['hydrantId'] as String? ?? '',
        allowed: json['allowed'] as bool? ?? false,
        source: _enum(
          FunctionalEligibilitySource.values,
          json['source'],
          FunctionalEligibilitySource.demo,
        ),
        reason: json['reason'] as String? ?? '',
        authorizedBy: json['authorizedBy'] as String? ?? '',
        authorizedRole: json['authorizedRole'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        authorizedAt: _date(json['authorizedAt']),
        pendingValidation: json['pendingValidation'] as bool? ?? false,
        supervisorValidationRequired:
            json['supervisorValidationRequired'] as bool? ?? false,
        visualReportRequired: json['visualReportRequired'] as bool? ?? false,
        visualReportId: json['visualReportId'] as String?,
        restrictions: _strings(json['restrictions']),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );
}

class FunctionalPreconditions {
  const FunctionalPreconditions({
    this.siteSafe,
    this.accessAllowed,
    this.authorizedPersonnel,
    this.responsibleIdentified,
    this.protectiveEquipment,
    this.hydraulicConditions,
    this.controlledDischarge,
    this.testBenchAvailable,
    this.instrumentsAvailable,
    this.calibrationValid,
    this.safeEnergy,
    this.authorizationAvailable,
    this.valvesIdentified,
    this.comments = '',
    this.visitWithoutTest = false,
    this.blockingReason = '',
    this.reschedulingRequired = false,
    this.evidencePhotoIds = const [],
  });
  final bool? siteSafe,
      accessAllowed,
      authorizedPersonnel,
      responsibleIdentified,
      protectiveEquipment,
      hydraulicConditions,
      controlledDischarge,
      testBenchAvailable,
      instrumentsAvailable,
      calibrationValid,
      safeEnergy,
      authorizationAvailable,
      valvesIdentified;
  final String comments, blockingReason;
  final bool visitWithoutTest, reschedulingRequired;
  final List<String> evidencePhotoIds;
  bool get criticalReady => [
    siteSafe,
    accessAllowed,
    authorizedPersonnel,
    responsibleIdentified,
    protectiveEquipment,
    hydraulicConditions,
    controlledDischarge,
    testBenchAvailable,
    instrumentsAvailable,
    calibrationValid,
    safeEnergy,
    authorizationAvailable,
    valvesIdentified,
  ].every((value) => value == true);
  Map<String, dynamic> toJson() => {
    'siteSafe': siteSafe,
    'accessAllowed': accessAllowed,
    'authorizedPersonnel': authorizedPersonnel,
    'responsibleIdentified': responsibleIdentified,
    'protectiveEquipment': protectiveEquipment,
    'hydraulicConditions': hydraulicConditions,
    'controlledDischarge': controlledDischarge,
    'testBenchAvailable': testBenchAvailable,
    'instrumentsAvailable': instrumentsAvailable,
    'calibrationValid': calibrationValid,
    'safeEnergy': safeEnergy,
    'authorizationAvailable': authorizationAvailable,
    'valvesIdentified': valvesIdentified,
    'comments': comments,
    'visitWithoutTest': visitWithoutTest,
    'blockingReason': blockingReason,
    'reschedulingRequired': reschedulingRequired,
    'evidencePhotoIds': evidencePhotoIds,
  };
  factory FunctionalPreconditions.fromJson(Map<String, dynamic> json) =>
      FunctionalPreconditions(
        siteSafe: json['siteSafe'] as bool?,
        accessAllowed: json['accessAllowed'] as bool?,
        authorizedPersonnel: json['authorizedPersonnel'] as bool?,
        responsibleIdentified: json['responsibleIdentified'] as bool?,
        protectiveEquipment: json['protectiveEquipment'] as bool?,
        hydraulicConditions: json['hydraulicConditions'] as bool?,
        controlledDischarge: json['controlledDischarge'] as bool?,
        testBenchAvailable: json['testBenchAvailable'] as bool?,
        instrumentsAvailable: json['instrumentsAvailable'] as bool?,
        calibrationValid: json['calibrationValid'] as bool?,
        safeEnergy: json['safeEnergy'] as bool?,
        authorizationAvailable: json['authorizationAvailable'] as bool?,
        valvesIdentified: json['valvesIdentified'] as bool?,
        comments: json['comments'] as String? ?? '',
        visitWithoutTest: json['visitWithoutTest'] as bool? ?? false,
        blockingReason: json['blockingReason'] as String? ?? '',
        reschedulingRequired: json['reschedulingRequired'] as bool? ?? false,
        evidencePhotoIds: _strings(json['evidencePhotoIds']),
      );
}

class InstrumentRecord {
  const InstrumentRecord({
    required this.id,
    required this.inspectionId,
    required this.type,
    this.assetCode = '',
    this.brandText = '',
    this.modelText = '',
    this.serialNumber = '',
    this.identificationStatus = InstrumentIdentificationStatus.identified,
    this.measurementRange = '',
    this.unit = '',
    this.accuracyClass = '',
    this.calibrationDate,
    this.calibrationDueDate,
    this.calibrationCertificate = '',
    this.calibrationStatus = CalibrationStatus.unknown,
    this.condition = '',
    this.operatorId = '',
    this.comments = '',
    this.photoIds = const [],
    this.deletedAt,
    this.lifecycleStatus = InstrumentLifecycleStatus.active,
    this.schemaVersion = 1,
  });
  final String id,
      inspectionId,
      type,
      assetCode,
      brandText,
      modelText,
      serialNumber,
      measurementRange,
      unit,
      accuracyClass,
      calibrationCertificate,
      condition,
      operatorId,
      comments;
  final InstrumentIdentificationStatus identificationStatus;
  final DateTime? calibrationDate, calibrationDueDate, deletedAt;
  final CalibrationStatus calibrationStatus;
  final InstrumentLifecycleStatus lifecycleStatus;
  final List<String> photoIds;
  final int schemaVersion;
  InstrumentRecord copyWith({
    String? type,
    String? assetCode,
    String? brandText,
    String? modelText,
    String? serialNumber,
    InstrumentIdentificationStatus? identificationStatus,
    String? measurementRange,
    String? unit,
    String? accuracyClass,
    DateTime? calibrationDate,
    DateTime? calibrationDueDate,
    String? calibrationCertificate,
    CalibrationStatus? calibrationStatus,
    String? condition,
    String? operatorId,
    String? comments,
    List<String>? photoIds,
    DateTime? deletedAt,
    bool restore = false,
    InstrumentLifecycleStatus? lifecycleStatus,
  }) => InstrumentRecord(
    id: id,
    inspectionId: inspectionId,
    type: type ?? this.type,
    assetCode: assetCode ?? this.assetCode,
    brandText: brandText ?? this.brandText,
    modelText: modelText ?? this.modelText,
    serialNumber: serialNumber ?? this.serialNumber,
    identificationStatus: identificationStatus ?? this.identificationStatus,
    measurementRange: measurementRange ?? this.measurementRange,
    unit: unit ?? this.unit,
    accuracyClass: accuracyClass ?? this.accuracyClass,
    calibrationDate: calibrationDate ?? this.calibrationDate,
    calibrationDueDate: calibrationDueDate ?? this.calibrationDueDate,
    calibrationCertificate:
        calibrationCertificate ?? this.calibrationCertificate,
    calibrationStatus: calibrationStatus ?? this.calibrationStatus,
    condition: condition ?? this.condition,
    operatorId: operatorId ?? this.operatorId,
    comments: comments ?? this.comments,
    photoIds: photoIds ?? this.photoIds,
    deletedAt: restore ? null : deletedAt ?? this.deletedAt,
    lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
    schemaVersion: schemaVersion,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'type': type,
    'assetCode': assetCode,
    'brandText': brandText,
    'modelText': modelText,
    'brand': brandText,
    'model': modelText,
    'serialNumber': serialNumber,
    'identificationStatus': identificationStatus.name,
    'measurementRange': measurementRange,
    'unit': unit,
    'accuracyClass': accuracyClass,
    'calibrationDate': _nullableDateToJson(calibrationDate),
    'calibrationDueDate': _nullableDateToJson(calibrationDueDate),
    'calibrationCertificate': calibrationCertificate,
    'calibrationStatus': calibrationStatus.name,
    'condition': condition,
    'operatorId': operatorId,
    'comments': comments,
    'photoIds': photoIds,
    'deletedAt': _nullableDateToJson(deletedAt),
    'lifecycleStatus': lifecycleStatus.name,
    'schemaVersion': schemaVersion,
  };
  factory InstrumentRecord.fromJson(
    Map<String, dynamic> json,
  ) => InstrumentRecord(
    id: json['id'] as String? ?? '',
    inspectionId: json['inspectionId'] as String? ?? '',
    type: json['type'] as String? ?? 'other',
    assetCode: json['assetCode'] as String? ?? '',
    brandText: json['brandText'] as String? ?? json['brand'] as String? ?? '',
    modelText: json['modelText'] as String? ?? json['model'] as String? ?? '',
    serialNumber: json['serialNumber'] as String? ?? '',
    identificationStatus: _enum(
      InstrumentIdentificationStatus.values,
      json['identificationStatus'],
      InstrumentIdentificationStatus.identified,
    ),
    measurementRange: json['measurementRange'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    accuracyClass: json['accuracyClass'] as String? ?? '',
    calibrationDate: _nullableDate(json['calibrationDate']),
    calibrationDueDate: _nullableDate(json['calibrationDueDate']),
    calibrationCertificate: json['calibrationCertificate'] as String? ?? '',
    calibrationStatus: _enum(
      CalibrationStatus.values,
      json['calibrationStatus'],
      CalibrationStatus.unknown,
    ),
    condition: json['condition'] as String? ?? '',
    operatorId: json['operatorId'] as String? ?? '',
    comments: json['comments'] as String? ?? '',
    photoIds: _strings(json['photoIds']),
    deletedAt: _nullableDate(json['deletedAt']),
    lifecycleStatus: _enum(
      InstrumentLifecycleStatus.values,
      json['lifecycleStatus'],
      json['deletedAt'] == null
          ? InstrumentLifecycleStatus.active
          : InstrumentLifecycleStatus.retired,
    ),
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );
}

class MeasurementReading {
  const MeasurementReading({
    required this.id,
    required this.timestamp,
    required this.originalValue,
    required this.originalUnit,
    required this.normalizedValue,
    required this.normalizedUnit,
    this.conversionVersion = 'units-v1',
    this.precision,
    this.source = MeasurementSource.manual,
    required this.instrumentId,
    required this.sequence,
    this.stable = false,
    this.accepted = true,
    this.rejectedReason = '',
    this.comments = '',
  });
  final String id,
      originalValue,
      originalUnit,
      normalizedValue,
      normalizedUnit,
      conversionVersion,
      instrumentId,
      rejectedReason,
      comments;
  final int? precision;
  final DateTime timestamp;
  final MeasurementSource source;
  final int sequence;
  final bool stable, accepted;
  MeasurementReading copyWith({
    bool? stable,
    bool? accepted,
    String? rejectedReason,
    String? comments,
  }) => MeasurementReading(
    id: id,
    timestamp: timestamp,
    originalValue: originalValue,
    originalUnit: originalUnit,
    normalizedValue: normalizedValue,
    normalizedUnit: normalizedUnit,
    conversionVersion: conversionVersion,
    precision: precision,
    source: source,
    instrumentId: instrumentId,
    sequence: sequence,
    stable: stable ?? this.stable,
    accepted: accepted ?? this.accepted,
    rejectedReason: rejectedReason ?? this.rejectedReason,
    comments: comments ?? this.comments,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': _dateToJson(timestamp),
    'originalValue': originalValue,
    'originalUnit': originalUnit,
    'normalizedValue': normalizedValue,
    'normalizedUnit': normalizedUnit,
    'conversionVersion': conversionVersion,
    'precision': precision,
    'source': source.name,
    'instrumentId': instrumentId,
    'sequence': sequence,
    'stable': stable,
    'accepted': accepted,
    'rejectedReason': rejectedReason,
    'comments': comments,
  };
  factory MeasurementReading.fromJson(Map<String, dynamic> json) =>
      MeasurementReading(
        id: json['id'] as String? ?? '',
        timestamp: _date(json['timestamp']),
        originalValue: '${json['originalValue'] ?? json['value'] ?? ''}',
        originalUnit:
            json['originalUnit'] as String? ?? json['unit'] as String? ?? '',
        normalizedValue: '${json['normalizedValue'] ?? json['value'] ?? ''}',
        normalizedUnit:
            json['normalizedUnit'] as String? ?? json['unit'] as String? ?? '',
        conversionVersion: json['conversionVersion'] as String? ?? 'units-v1',
        precision: json['precision'] as int?,
        source: _enum(
          MeasurementSource.values,
          json['source'],
          MeasurementSource.manual,
        ),
        instrumentId: json['instrumentId'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        stable: json['stable'] as bool? ?? false,
        accepted: json['accepted'] as bool? ?? true,
        rejectedReason: json['rejectedReason'] as String? ?? '',
        comments: json['comments'] as String? ?? '',
      );
}

class MeasurementSeries {
  const MeasurementSeries({
    required this.id,
    required this.inspectionId,
    required this.testType,
    required this.instrumentId,
    this.componentId,
    this.valveId,
    required this.startedAt,
    this.completedAt,
    required this.unit,
    this.expectedRange = '',
    this.readings = const [],
    this.result = '',
    this.comments = '',
    required this.createdBy,
    required this.deviceId,
    this.schemaVersion = 1,
  });
  final String id,
      inspectionId,
      testType,
      instrumentId,
      unit,
      expectedRange,
      result,
      comments,
      createdBy,
      deviceId;
  final String? componentId, valveId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<MeasurementReading> readings;
  final int schemaVersion;
  bool get isActive => completedAt == null;
  MeasurementSeries copyWith({
    DateTime? completedAt,
    List<MeasurementReading>? readings,
    String? result,
    String? comments,
  }) => MeasurementSeries(
    id: id,
    inspectionId: inspectionId,
    testType: testType,
    instrumentId: instrumentId,
    componentId: componentId,
    valveId: valveId,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
    unit: unit,
    expectedRange: expectedRange,
    readings: readings ?? this.readings,
    result: result ?? this.result,
    comments: comments ?? this.comments,
    createdBy: createdBy,
    deviceId: deviceId,
    schemaVersion: schemaVersion,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'testType': testType,
    'instrumentId': instrumentId,
    'componentId': componentId,
    'valveId': valveId,
    'startedAt': _dateToJson(startedAt),
    'completedAt': _nullableDateToJson(completedAt),
    'unit': unit,
    'expectedRange': expectedRange,
    'readings': readings.map((value) => value.toJson()).toList(),
    'result': result,
    'comments': comments,
    'createdBy': createdBy,
    'deviceId': deviceId,
    'schemaVersion': schemaVersion,
  };
  factory MeasurementSeries.fromJson(Map<String, dynamic> json) =>
      MeasurementSeries(
        id: json['id'] as String? ?? '',
        inspectionId: json['inspectionId'] as String? ?? '',
        testType: json['testType'] as String? ?? '',
        instrumentId: json['instrumentId'] as String? ?? '',
        componentId: json['componentId'] as String?,
        valveId: json['valveId'] as String?,
        startedAt: _date(json['startedAt']),
        completedAt: _nullableDate(json['completedAt']),
        unit: json['unit'] as String? ?? '',
        expectedRange: json['expectedRange'] as String? ?? '',
        readings: [
          for (final value in json['readings'] as List? ?? const [])
            MeasurementReading.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
        ],
        result: json['result'] as String? ?? '',
        comments: json['comments'] as String? ?? '',
        createdBy: json['createdBy'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );
}

abstract class FunctionalTestRecord {
  const FunctionalTestRecord({
    required this.id,
    required this.inspectionId,
    this.result = '',
    this.comments = '',
    this.schemaVersion = 1,
  });
  final String id, inspectionId, result, comments;
  final int schemaVersion;
  Map<String, dynamic> fields();
  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'result': result,
    'comments': comments,
    'schemaVersion': schemaVersion,
    ...fields(),
  };
}

class PressureTest extends FunctionalTestRecord {
  const PressureTest({
    required super.id,
    required super.inspectionId,
    this.seriesIds = const [],
    this.stability = '',
    this.oscillation = '',
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final List<String> seriesIds;
  final String stability, oscillation;
  @override
  Map<String, dynamic> fields() => {
    'type': 'pressure',
    'seriesIds': seriesIds,
    'stability': stability,
    'oscillation': oscillation,
  };
  factory PressureTest.fromJson(Map<String, dynamic> j) => PressureTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    seriesIds: _strings(j['seriesIds']),
    stability: j['stability'] as String? ?? '',
    oscillation: j['oscillation'] as String? ?? '',
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class FlowTest extends FunctionalTestRecord {
  const FlowTest({
    required super.id,
    required super.inspectionId,
    this.hydrantSeriesId,
    this.patternSeriesId,
    this.expectedFlow = '',
    this.durationSeconds = '',
    this.volume = '',
    this.stability = '',
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final String? hydrantSeriesId, patternSeriesId;
  final String expectedFlow, durationSeconds, volume, stability;
  @override
  Map<String, dynamic> fields() => {
    'type': 'flow',
    'hydrantSeriesId': hydrantSeriesId,
    'patternSeriesId': patternSeriesId,
    'expectedFlow': expectedFlow,
    'durationSeconds': durationSeconds,
    'volume': volume,
    'stability': stability,
  };
  factory FlowTest.fromJson(Map<String, dynamic> j) => FlowTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    hydrantSeriesId: j['hydrantSeriesId'] as String?,
    patternSeriesId: j['patternSeriesId'] as String?,
    expectedFlow: j['expectedFlow'] as String? ?? '',
    durationSeconds: j['durationSeconds'] as String? ?? '',
    volume: j['volume'] as String? ?? '',
    stability: j['stability'] as String? ?? '',
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class FunctionalValveTest extends FunctionalTestRecord {
  const FunctionalValveTest({
    required super.id,
    required super.inspectionId,
    required this.valveId,
    this.diameter = '',
    this.testSequence = 1,
    this.openingTimeSeconds = '',
    this.closingTimeSeconds = '',
    this.numberOfCycles = 1,
    this.manualOperation = '',
    this.automaticOperation = '',
    this.effort = '',
    this.blockage = false,
    this.noise = false,
    this.vibration = false,
    this.leakageLevel = '',
    this.pressureBehavior = '',
    this.photoIds = const [],
    this.instrumentIds = const [],
    this.measurementSeriesIds = const [],
    this.accepted = false,
    this.invalidatedAt,
    this.invalidatedBy,
    this.invalidationReason,
    this.createdAt,
    this.updatedAt,
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final String valveId,
      diameter,
      openingTimeSeconds,
      closingTimeSeconds,
      manualOperation,
      automaticOperation,
      effort,
      leakageLevel,
      pressureBehavior;
  final int testSequence, numberOfCycles;
  final bool blockage, noise, vibration;
  final bool accepted;
  final List<String> photoIds, instrumentIds, measurementSeriesIds;
  final DateTime? invalidatedAt, createdAt, updatedAt;
  final String? invalidatedBy, invalidationReason;
  bool get valid => invalidatedAt == null;
  @override
  Map<String, dynamic> fields() => {
    'type': 'valve',
    'valveId': valveId,
    'diameter': diameter,
    'testSequence': testSequence,
    'openingTimeSeconds': openingTimeSeconds,
    'closingTimeSeconds': closingTimeSeconds,
    'numberOfCycles': numberOfCycles,
    'manualOperation': manualOperation,
    'automaticOperation': automaticOperation,
    'effort': effort,
    'blockage': blockage,
    'noise': noise,
    'vibration': vibration,
    'leakageLevel': leakageLevel,
    'pressureBehavior': pressureBehavior,
    'photoIds': photoIds,
    'instrumentIds': instrumentIds,
    'measurementSeriesIds': measurementSeriesIds,
    'accepted': accepted,
    'invalidatedAt': _nullableDateToJson(invalidatedAt),
    'invalidatedBy': invalidatedBy,
    'invalidationReason': invalidationReason,
    'createdAt': _nullableDateToJson(createdAt),
    'updatedAt': _nullableDateToJson(updatedAt),
  };
  factory FunctionalValveTest.fromJson(Map<String, dynamic> j) =>
      FunctionalValveTest(
        id: j['id'] as String? ?? '',
        inspectionId: j['inspectionId'] as String? ?? '',
        valveId: j['valveId'] as String? ?? '',
        diameter: j['diameter'] as String? ?? '',
        testSequence: j['testSequence'] as int? ?? 1,
        openingTimeSeconds: j['openingTimeSeconds'] as String? ?? '',
        closingTimeSeconds: j['closingTimeSeconds'] as String? ?? '',
        numberOfCycles: j['numberOfCycles'] as int? ?? 1,
        manualOperation: j['manualOperation'] as String? ?? '',
        automaticOperation: j['automaticOperation'] as String? ?? '',
        effort: j['effort'] as String? ?? '',
        blockage: j['blockage'] as bool? ?? false,
        noise: j['noise'] as bool? ?? false,
        vibration: j['vibration'] as bool? ?? false,
        leakageLevel: j['leakageLevel'] as String? ?? '',
        pressureBehavior: j['pressureBehavior'] as String? ?? '',
        photoIds: _strings(j['photoIds']),
        instrumentIds: _strings(j['instrumentIds']),
        measurementSeriesIds: _strings(j['measurementSeriesIds']),
        accepted: j['accepted'] as bool? ?? false,
        invalidatedAt: _nullableDate(j['invalidatedAt']),
        invalidatedBy: j['invalidatedBy'] as String?,
        invalidationReason: j['invalidationReason'] as String?,
        createdAt: _nullableDate(j['createdAt']),
        updatedAt: _nullableDate(j['updatedAt']),
        result: j['result'] as String? ?? '',
        comments: j['comments'] as String? ?? '',
        schemaVersion: j['schemaVersion'] as int? ?? 1,
      );
}

class ReducerTest extends FunctionalTestRecord {
  const ReducerTest({
    required super.id,
    required super.inspectionId,
    this.runs = const [],
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final List<Map<String, dynamic>> runs;
  @override
  Map<String, dynamic> fields() => {'type': 'reducer', 'runs': runs};
  factory ReducerTest.fromJson(Map<String, dynamic> j) => ReducerTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    runs: [
      for (final v in j['runs'] as List? ?? const [])
        Map<String, dynamic>.from(v as Map),
    ],
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class SolenoidTest extends FunctionalTestRecord {
  const SolenoidTest({
    required super.id,
    required super.inspectionId,
    this.values = const {},
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> fields() => {'type': 'solenoid', 'values': values};
  factory SolenoidTest.fromJson(Map<String, dynamic> j) => SolenoidTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    values: Map<String, dynamic>.from(j['values'] as Map? ?? {}),
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class EnergyTest extends FunctionalTestRecord {
  const EnergyTest({
    required super.id,
    required super.inspectionId,
    this.values = const {},
    this.notPerformedReason = '',
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final Map<String, dynamic> values;
  final String notPerformedReason;
  @override
  Map<String, dynamic> fields() => {
    'type': 'energy',
    'values': values,
    'notPerformedReason': notPerformedReason,
  };
  factory EnergyTest.fromJson(Map<String, dynamic> j) => EnergyTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    values: Map<String, dynamic>.from(j['values'] as Map? ?? {}),
    notPerformedReason: j['notPerformedReason'] as String? ?? '',
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class CommunicationTest extends FunctionalTestRecord {
  const CommunicationTest({
    required super.id,
    required super.inspectionId,
    this.values = const {},
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> fields() => {'type': 'communication', 'values': values};
  factory CommunicationTest.fromJson(Map<String, dynamic> j) =>
      CommunicationTest(
        id: j['id'] as String? ?? '',
        inspectionId: j['inspectionId'] as String? ?? '',
        values: Map<String, dynamic>.from(j['values'] as Map? ?? {}),
        result: j['result'] as String? ?? '',
        comments: j['comments'] as String? ?? '',
        schemaVersion: j['schemaVersion'] as int? ?? 1,
      );
}

class AlarmTest extends FunctionalTestRecord {
  const AlarmTest({
    required super.id,
    required super.inspectionId,
    required this.alarmType,
    this.generated = false,
    this.detectedLocally = false,
    this.reported = false,
    this.generatedAt,
    this.reportedAt,
    this.latencyMs = '',
    this.acknowledged = false,
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final String alarmType, latencyMs;
  final bool generated, detectedLocally, reported, acknowledged;
  final DateTime? generatedAt, reportedAt;
  @override
  Map<String, dynamic> fields() => {
    'type': 'alarm',
    'alarmType': alarmType,
    'generated': generated,
    'detectedLocally': detectedLocally,
    'reported': reported,
    'generatedAt': _nullableDateToJson(generatedAt),
    'reportedAt': _nullableDateToJson(reportedAt),
    'latencyMs': latencyMs,
    'acknowledged': acknowledged,
  };
  factory AlarmTest.fromJson(Map<String, dynamic> j) => AlarmTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    alarmType: j['alarmType'] as String? ?? '',
    generated: j['generated'] as bool? ?? false,
    detectedLocally: j['detectedLocally'] as bool? ?? false,
    reported: j['reported'] as bool? ?? false,
    generatedAt: _nullableDate(j['generatedAt']),
    reportedAt: _nullableDate(j['reportedAt']),
    latencyMs: j['latencyMs'] as String? ?? '',
    acknowledged: j['acknowledged'] as bool? ?? false,
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class LeakageTest extends FunctionalTestRecord {
  const LeakageTest({
    required super.id,
    required super.inspectionId,
    this.level = 'none',
    this.location = '',
    this.componentId = '',
    this.pressure = '',
    this.durationSeconds = '',
    this.estimatedLoss = '',
    this.recommendedAction = '',
    this.photoIds = const [],
    super.result = '',
    super.comments = '',
    super.schemaVersion = 1,
  });
  final String level,
      location,
      componentId,
      pressure,
      durationSeconds,
      estimatedLoss,
      recommendedAction;
  final List<String> photoIds;
  @override
  Map<String, dynamic> fields() => {
    'type': 'leakage',
    'level': level,
    'location': location,
    'componentId': componentId,
    'pressure': pressure,
    'durationSeconds': durationSeconds,
    'estimatedLoss': estimatedLoss,
    'recommendedAction': recommendedAction,
    'photoIds': photoIds,
  };
  factory LeakageTest.fromJson(Map<String, dynamic> j) => LeakageTest(
    id: j['id'] as String? ?? '',
    inspectionId: j['inspectionId'] as String? ?? '',
    level: j['level'] as String? ?? 'none',
    location: j['location'] as String? ?? '',
    componentId: j['componentId'] as String? ?? '',
    pressure: j['pressure'] as String? ?? '',
    durationSeconds: j['durationSeconds'] as String? ?? '',
    estimatedLoss: j['estimatedLoss'] as String? ?? '',
    recommendedAction: j['recommendedAction'] as String? ?? '',
    photoIds: _strings(j['photoIds']),
    result: j['result'] as String? ?? '',
    comments: j['comments'] as String? ?? '',
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

class FunctionalInspectionResult {
  const FunctionalInspectionResult({
    this.overallResult,
    this.hydraulicResult = '',
    this.mechanicalResult = '',
    this.electricalResult = '',
    this.communicationResult = '',
    this.safetyResult = '',
    this.calibrationResult = '',
    this.operationalStatus = '',
    this.restrictions = const [],
    this.requiresRepair = false,
    this.requiresReplacement = false,
    this.requiresAdjustment = false,
    this.requiresRepeatTest = false,
    this.requiresSupervisorReview = false,
    this.priority = '',
    this.recommendedActions = const [],
    this.finalComments = '',
    this.calculatedResult,
    this.calculationRulesVersion = 'functional-result-demo-v1',
    this.inspectorOverrideReason = '',
    this.completedAt,
    this.completedBy = '',
  });
  final FunctionalOverallResult? overallResult, calculatedResult;
  final String hydraulicResult,
      mechanicalResult,
      electricalResult,
      communicationResult,
      safetyResult,
      calibrationResult,
      operationalStatus,
      priority,
      finalComments,
      calculationRulesVersion,
      inspectorOverrideReason,
      completedBy;
  final List<String> restrictions, recommendedActions;
  final bool requiresRepair,
      requiresReplacement,
      requiresAdjustment,
      requiresRepeatTest,
      requiresSupervisorReview;
  final DateTime? completedAt;
  Map<String, dynamic> toJson() => {
    'overallResult': overallResult?.name,
    'hydraulicResult': hydraulicResult,
    'mechanicalResult': mechanicalResult,
    'electricalResult': electricalResult,
    'communicationResult': communicationResult,
    'safetyResult': safetyResult,
    'calibrationResult': calibrationResult,
    'operationalStatus': operationalStatus,
    'restrictions': restrictions,
    'requiresRepair': requiresRepair,
    'requiresReplacement': requiresReplacement,
    'requiresAdjustment': requiresAdjustment,
    'requiresRepeatTest': requiresRepeatTest,
    'requiresSupervisorReview': requiresSupervisorReview,
    'priority': priority,
    'recommendedActions': recommendedActions,
    'finalComments': finalComments,
    'calculatedResult': calculatedResult?.name,
    'calculationRulesVersion': calculationRulesVersion,
    'inspectorOverrideReason': inspectorOverrideReason,
    'completedAt': _nullableDateToJson(completedAt),
    'completedBy': completedBy,
  };
  factory FunctionalInspectionResult.fromJson(
    Map<String, dynamic> j,
  ) => FunctionalInspectionResult(
    overallResult: _enumNullable(
      FunctionalOverallResult.values,
      j['overallResult'],
    ),
    hydraulicResult: j['hydraulicResult'] as String? ?? '',
    mechanicalResult: j['mechanicalResult'] as String? ?? '',
    electricalResult: j['electricalResult'] as String? ?? '',
    communicationResult: j['communicationResult'] as String? ?? '',
    safetyResult: j['safetyResult'] as String? ?? '',
    calibrationResult: j['calibrationResult'] as String? ?? '',
    operationalStatus: j['operationalStatus'] as String? ?? '',
    restrictions: _strings(j['restrictions']),
    requiresRepair: j['requiresRepair'] as bool? ?? false,
    requiresReplacement: j['requiresReplacement'] as bool? ?? false,
    requiresAdjustment: j['requiresAdjustment'] as bool? ?? false,
    requiresRepeatTest: j['requiresRepeatTest'] as bool? ?? false,
    requiresSupervisorReview: j['requiresSupervisorReview'] as bool? ?? false,
    priority: j['priority'] as String? ?? '',
    recommendedActions: _strings(j['recommendedActions']),
    finalComments: j['finalComments'] as String? ?? '',
    calculatedResult: _enumNullable(
      FunctionalOverallResult.values,
      j['calculatedResult'],
    ),
    calculationRulesVersion:
        j['calculationRulesVersion'] as String? ?? 'functional-result-demo-v1',
    inspectorOverrideReason: j['inspectorOverrideReason'] as String? ?? '',
    completedAt: _nullableDate(j['completedAt']),
    completedBy: j['completedBy'] as String? ?? '',
  );
}

class FunctionalFieldProvenance {
  const FunctionalFieldProvenance({
    required this.fieldKey,
    this.visualInspectionId,
    this.inheritedValue,
    this.observedValue,
    this.reason = '',
    required this.observedBy,
    required this.observedAt,
    this.reviewRequired = false,
  });
  final String fieldKey, reason, observedBy;
  final String? visualInspectionId;
  final Object? inheritedValue, observedValue;
  final DateTime observedAt;
  final bool reviewRequired;
  Map<String, dynamic> toJson() => {
    'fieldKey': fieldKey,
    'visualInspectionId': visualInspectionId,
    'inheritedValue': inheritedValue,
    'observedValue': observedValue,
    'reason': reason,
    'observedBy': observedBy,
    'observedAt': _dateToJson(observedAt),
    'reviewRequired': reviewRequired,
  };
  factory FunctionalFieldProvenance.fromJson(Map<String, dynamic> j) =>
      FunctionalFieldProvenance(
        fieldKey: j['fieldKey'] as String? ?? '',
        visualInspectionId: j['visualInspectionId'] as String?,
        inheritedValue: j['inheritedValue'],
        observedValue: j['observedValue'],
        reason: j['reason'] as String? ?? '',
        observedBy: j['observedBy'] as String? ?? '',
        observedAt: _date(j['observedAt']),
        reviewRequired: j['reviewRequired'] as bool? ?? false,
      );
}

class EvidenceRequirement {
  const EvidenceRequirement({
    required this.id,
    required this.category,
    this.status = EvidenceRequirementStatus.pending,
    this.reason = '',
    this.photoIds = const [],
    this.testId,
  });
  final String id, category, reason;
  final EvidenceRequirementStatus status;
  final List<String> photoIds;
  final String? testId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'status': status.name,
    'reason': reason,
    'photoIds': photoIds,
    'testId': testId,
  };
  factory EvidenceRequirement.fromJson(Map<String, dynamic> j) =>
      EvidenceRequirement(
        id: j['id'] as String? ?? '',
        category: j['category'] as String? ?? '',
        status: _enum(
          EvidenceRequirementStatus.values,
          j['status'],
          EvidenceRequirementStatus.pending,
        ),
        reason: j['reason'] as String? ?? '',
        photoIds: _strings(j['photoIds']),
        testId: j['testId'] as String?,
      );
}

class FunctionalInspection {
  const FunctionalInspection({
    required this.id,
    required this.hydrantId,
    this.assignmentId,
    required this.source,
    this.status = FunctionalInspectionStatus.draft,
    this.currentStep = 1,
    this.currentSubstep = 1,
    required this.inspectorId,
    required this.inspectorName,
    required this.brigadeId,
    required this.brigadeName,
    required this.deviceId,
    required this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.pauseReason = '',
    this.suspensionReason = '',
    this.visitWithoutTest = false,
    this.parallelTestAuthorizationId,
    this.repeatOfInspectionId,
    this.visualInspectionId,
    this.preconditions = const FunctionalPreconditions(),
    this.instrumentIds = const [],
    this.measurementSeriesIds = const [],
    this.testRecordIds = const [],
    this.photoIds = const [],
    this.evidenceRequirements = const [],
    this.provenance = const [],
    this.stepData = const {},
    this.result = const FunctionalInspectionResult(),
    this.revisionOfReportId,
    this.revisionNumber = 0,
    this.previousRevisionId,
    this.revisionReason = '',
    this.activeRevision = true,
    this.supervisorReviewRequired = false,
    this.schemaVersion = 1,
  });
  final String id,
      hydrantId,
      inspectorId,
      inspectorName,
      brigadeId,
      brigadeName,
      deviceId,
      pauseReason,
      suspensionReason;
  final String? assignmentId,
      parallelTestAuthorizationId,
      repeatOfInspectionId,
      visualInspectionId;
  final String? revisionOfReportId, previousRevisionId;
  final String revisionReason;
  final HydrantSource source;
  final FunctionalInspectionStatus status;
  final int currentStep, currentSubstep, schemaVersion, revisionNumber;
  final DateTime startedAt, createdAt, updatedAt;
  final DateTime? completedAt;
  final bool visitWithoutTest;
  final bool activeRevision, supervisorReviewRequired;
  final FunctionalPreconditions preconditions;
  final List<String> instrumentIds,
      measurementSeriesIds,
      testRecordIds,
      photoIds;
  final List<EvidenceRequirement> evidenceRequirements;
  final List<FunctionalFieldProvenance> provenance;
  final Map<String, dynamic> stepData;
  final FunctionalInspectionResult result;
  double get progress => currentStep.clamp(1, 10) / 10;
  FunctionalInspection copyWith({
    FunctionalInspectionStatus? status,
    int? currentStep,
    int? currentSubstep,
    DateTime? completedAt,
    DateTime? updatedAt,
    String? pauseReason,
    String? suspensionReason,
    String? visualInspectionId,
    bool? visitWithoutTest,
    FunctionalPreconditions? preconditions,
    List<String>? instrumentIds,
    List<String>? measurementSeriesIds,
    List<String>? testRecordIds,
    List<String>? photoIds,
    List<EvidenceRequirement>? evidenceRequirements,
    List<FunctionalFieldProvenance>? provenance,
    Map<String, dynamic>? stepData,
    FunctionalInspectionResult? result,
    String? revisionOfReportId,
    int? revisionNumber,
    String? previousRevisionId,
    String? revisionReason,
    bool? activeRevision,
    bool? supervisorReviewRequired,
  }) => FunctionalInspection(
    id: id,
    hydrantId: hydrantId,
    assignmentId: assignmentId,
    source: source,
    status: status ?? this.status,
    currentStep: currentStep ?? this.currentStep,
    currentSubstep: currentSubstep ?? this.currentSubstep,
    inspectorId: inspectorId,
    inspectorName: inspectorName,
    brigadeId: brigadeId,
    brigadeName: brigadeName,
    deviceId: deviceId,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    pauseReason: pauseReason ?? this.pauseReason,
    suspensionReason: suspensionReason ?? this.suspensionReason,
    visitWithoutTest: visitWithoutTest ?? this.visitWithoutTest,
    parallelTestAuthorizationId: parallelTestAuthorizationId,
    repeatOfInspectionId: repeatOfInspectionId,
    visualInspectionId: visualInspectionId ?? this.visualInspectionId,
    preconditions: preconditions ?? this.preconditions,
    instrumentIds: instrumentIds ?? this.instrumentIds,
    measurementSeriesIds: measurementSeriesIds ?? this.measurementSeriesIds,
    testRecordIds: testRecordIds ?? this.testRecordIds,
    photoIds: photoIds ?? this.photoIds,
    evidenceRequirements: evidenceRequirements ?? this.evidenceRequirements,
    provenance: provenance ?? this.provenance,
    stepData: stepData ?? this.stepData,
    result: result ?? this.result,
    revisionOfReportId: revisionOfReportId ?? this.revisionOfReportId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
    previousRevisionId: previousRevisionId ?? this.previousRevisionId,
    revisionReason: revisionReason ?? this.revisionReason,
    activeRevision: activeRevision ?? this.activeRevision,
    supervisorReviewRequired:
        supervisorReviewRequired ?? this.supervisorReviewRequired,
    schemaVersion: schemaVersion,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'hydrantId': hydrantId,
    'assignmentId': assignmentId,
    'source': source.name,
    'status': status.name,
    'currentStep': currentStep,
    'currentSubstep': currentSubstep,
    'inspectorId': inspectorId,
    'inspectorName': inspectorName,
    'brigadeId': brigadeId,
    'brigadeName': brigadeName,
    'deviceId': deviceId,
    'startedAt': _dateToJson(startedAt),
    'completedAt': _nullableDateToJson(completedAt),
    'createdAt': _dateToJson(createdAt),
    'updatedAt': _dateToJson(updatedAt),
    'pauseReason': pauseReason,
    'suspensionReason': suspensionReason,
    'visitWithoutTest': visitWithoutTest,
    'parallelTestAuthorizationId': parallelTestAuthorizationId,
    'repeatOfInspectionId': repeatOfInspectionId,
    'visualInspectionId': visualInspectionId,
    'preconditions': preconditions.toJson(),
    'instrumentIds': instrumentIds,
    'measurementSeriesIds': measurementSeriesIds,
    'testRecordIds': testRecordIds,
    'photoIds': photoIds,
    'evidenceRequirements': evidenceRequirements
        .map((v) => v.toJson())
        .toList(),
    'provenance': provenance.map((v) => v.toJson()).toList(),
    'stepData': stepData,
    'result': result.toJson(),
    'revisionOfReportId': revisionOfReportId,
    'revisionNumber': revisionNumber,
    'previousRevisionId': previousRevisionId,
    'revisionReason': revisionReason,
    'activeRevision': activeRevision,
    'supervisorReviewRequired': supervisorReviewRequired,
    'schemaVersion': schemaVersion,
  };
  factory FunctionalInspection.fromJson(
    Map<String, dynamic> j,
  ) => FunctionalInspection(
    id: j['id'] as String? ?? '',
    hydrantId: j['hydrantId'] as String? ?? '',
    assignmentId: j['assignmentId'] as String?,
    source: _enum(HydrantSource.values, j['source'], HydrantSource.assigned),
    status: _enum(
      FunctionalInspectionStatus.values,
      j['status'],
      FunctionalInspectionStatus.draft,
    ),
    currentStep: j['currentStep'] as int? ?? 1,
    currentSubstep: j['currentSubstep'] as int? ?? 1,
    inspectorId: j['inspectorId'] as String? ?? '',
    inspectorName: j['inspectorName'] as String? ?? '',
    brigadeId: j['brigadeId'] as String? ?? '',
    brigadeName: j['brigadeName'] as String? ?? '',
    deviceId: j['deviceId'] as String? ?? '',
    startedAt: _date(j['startedAt']),
    completedAt: _nullableDate(j['completedAt']),
    createdAt: _date(j['createdAt']),
    updatedAt: _date(j['updatedAt']),
    pauseReason: j['pauseReason'] as String? ?? '',
    suspensionReason: j['suspensionReason'] as String? ?? '',
    visitWithoutTest: j['visitWithoutTest'] as bool? ?? false,
    parallelTestAuthorizationId: j['parallelTestAuthorizationId'] as String?,
    repeatOfInspectionId: j['repeatOfInspectionId'] as String?,
    visualInspectionId: j['visualInspectionId'] as String?,
    preconditions: FunctionalPreconditions.fromJson(
      Map<String, dynamic>.from(j['preconditions'] as Map? ?? {}),
    ),
    instrumentIds: _strings(j['instrumentIds']),
    measurementSeriesIds: _strings(j['measurementSeriesIds']),
    testRecordIds: _strings(j['testRecordIds']),
    photoIds: _strings(j['photoIds']),
    evidenceRequirements: [
      for (final v in j['evidenceRequirements'] as List? ?? const [])
        EvidenceRequirement.fromJson(Map<String, dynamic>.from(v as Map)),
    ],
    provenance: [
      for (final v in j['provenance'] as List? ?? const [])
        FunctionalFieldProvenance.fromJson(Map<String, dynamic>.from(v as Map)),
    ],
    stepData: Map<String, dynamic>.from(j['stepData'] as Map? ?? {}),
    result: FunctionalInspectionResult.fromJson(
      Map<String, dynamic>.from(j['result'] as Map? ?? {}),
    ),
    revisionOfReportId: j['revisionOfReportId'] as String?,
    revisionNumber: j['revisionNumber'] as int? ?? 0,
    previousRevisionId: j['previousRevisionId'] as String?,
    revisionReason: j['revisionReason'] as String? ?? '',
    activeRevision: j['activeRevision'] as bool? ?? true,
    supervisorReviewRequired: j['supervisorReviewRequired'] as bool? ?? false,
    schemaVersion: j['schemaVersion'] as int? ?? 1,
  );
}

String _dateToJson(DateTime value) => value.toUtc().toIso8601String();
String? _nullableDateToJson(DateTime? value) =>
    value?.toUtc().toIso8601String();
DateTime _date(Object? value) =>
    DateTime.tryParse(value as String? ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
DateTime? _nullableDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((v) => '$v').toList();
T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

T? _enumNullable<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
