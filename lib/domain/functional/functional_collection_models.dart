class ValveRecord {
  const ValveRecord({
    required this.id,
    required this.inspectionId,
    required this.order,
    required this.label,
    this.type = '',
    this.diameter = '',
    this.initialPosition = '',
    this.configuration = const {},
    this.testIds = const [],
    this.photoIds = const [],
    this.seriesIds = const [],
    this.instrumentIds = const [],
    this.result = '',
    this.retiredAt,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });
  final String id, inspectionId, label, type, diameter, initialPosition, result;
  final int order, schemaVersion;
  final Map<String, dynamic> configuration;
  final List<String> testIds, photoIds, seriesIds, instrumentIds;
  final DateTime createdAt, updatedAt;
  final DateTime? retiredAt;
  bool get active => retiredAt == null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'order': order,
    'label': label,
    'type': type,
    'diameter': diameter,
    'initialPosition': initialPosition,
    'configuration': configuration,
    'testIds': testIds,
    'photoIds': photoIds,
    'seriesIds': seriesIds,
    'instrumentIds': instrumentIds,
    'result': result,
    'retiredAt': retiredAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory ValveRecord.fromJson(Map<String, dynamic> json) => ValveRecord(
    id: json['id'] as String? ?? '',
    inspectionId: json['inspectionId'] as String? ?? '',
    order: json['order'] as int? ?? 0,
    label: json['label'] as String? ?? '',
    type: json['type'] as String? ?? '',
    diameter: json['diameter'] as String? ?? '',
    initialPosition: json['initialPosition'] as String? ?? '',
    configuration: Map<String, dynamic>.from(
      json['configuration'] as Map? ?? const {},
    ),
    testIds: _strings(json['testIds']),
    photoIds: _strings(json['photoIds']),
    seriesIds: _strings(json['seriesIds']),
    instrumentIds: _strings(json['instrumentIds']),
    result: json['result'] as String? ?? '',
    retiredAt: _nullableDate(json['retiredAt']),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );
}

class ReducerRun {
  const ReducerRun({
    required this.reducerRunId,
    required this.reducerId,
    required this.inspectionId,
    required this.order,
    required this.conditionKey,
    this.flowRangeMin,
    this.flowRangeMax,
    this.flowUnit = 'L/s',
    this.inletPressure = '',
    this.targetPressure = '',
    this.outletPressure = '',
    this.flow = '',
    this.stability = '',
    this.adjustment = '',
    this.instrumentIds = const [],
    this.measurementSeriesIds = const [],
    this.photoIds = const [],
    this.result = '',
    this.accepted = false,
    this.invalidatedAt,
    this.invalidatedBy,
    this.invalidationReason,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });
  final String reducerRunId, reducerId, inspectionId, conditionKey, flowUnit;
  final String inletPressure, targetPressure, outletPressure, flow;
  final String stability, adjustment, result;
  final String? invalidatedBy, invalidationReason;
  final int order, schemaVersion;
  final double? flowRangeMin, flowRangeMax;
  final List<String> instrumentIds, measurementSeriesIds, photoIds;
  final bool accepted;
  final DateTime? invalidatedAt;
  final DateTime createdAt, updatedAt;
  bool get valid => invalidatedAt == null;
  Map<String, dynamic> toJson() => {
    'reducerRunId': reducerRunId,
    'reducerId': reducerId,
    'inspectionId': inspectionId,
    'order': order,
    'conditionKey': conditionKey,
    'flowRangeMin': flowRangeMin,
    'flowRangeMax': flowRangeMax,
    'flowUnit': flowUnit,
    'inletPressure': inletPressure,
    'targetPressure': targetPressure,
    'outletPressure': outletPressure,
    'flow': flow,
    'stability': stability,
    'adjustment': adjustment,
    'instrumentIds': instrumentIds,
    'measurementSeriesIds': measurementSeriesIds,
    'photoIds': photoIds,
    'result': result,
    'accepted': accepted,
    'invalidatedAt': invalidatedAt?.toUtc().toIso8601String(),
    'invalidatedBy': invalidatedBy,
    'invalidationReason': invalidationReason,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory ReducerRun.fromJson(Map<String, dynamic> json) => ReducerRun(
    reducerRunId: json['reducerRunId'] as String? ?? '',
    reducerId: json['reducerId'] as String? ?? '',
    inspectionId: json['inspectionId'] as String? ?? '',
    order: json['order'] as int? ?? 0,
    conditionKey: json['conditionKey'] as String? ?? 'default',
    flowRangeMin: (json['flowRangeMin'] as num?)?.toDouble(),
    flowRangeMax: (json['flowRangeMax'] as num?)?.toDouble(),
    flowUnit: json['flowUnit'] as String? ?? 'L/s',
    inletPressure: '${json['inletPressure'] ?? ''}',
    targetPressure: '${json['targetPressure'] ?? ''}',
    outletPressure: '${json['outletPressure'] ?? ''}',
    flow: '${json['flow'] ?? ''}',
    stability: json['stability'] as String? ?? '',
    adjustment: json['adjustment'] as String? ?? '',
    instrumentIds: _strings(json['instrumentIds']),
    measurementSeriesIds: _strings(json['measurementSeriesIds']),
    photoIds: _strings(json['photoIds']),
    result: json['result'] as String? ?? '',
    accepted: json['accepted'] as bool? ?? false,
    invalidatedAt: _nullableDate(json['invalidatedAt']),
    invalidatedBy: json['invalidatedBy'] as String?,
    invalidationReason: json['invalidationReason'] as String?,
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );
}

class AlarmAttemptRecord {
  const AlarmAttemptRecord({
    required this.id,
    required this.inspectionId,
    required this.alarmType,
    this.otherDescription = '',
    required this.attemptNumber,
    this.generated = false,
    this.detectedLocally = false,
    this.reported = false,
    this.generatedAt,
    this.detectedAt,
    this.reportedAt,
    this.acknowledgedAt,
    this.latencyMs,
    this.acknowledged = false,
    this.result = '',
    this.comments = '',
    this.photoIds = const [],
    this.invalidatedAt,
    this.invalidatedBy,
    this.invalidationReason,
    required this.createdAt,
    this.updatedAt,
    this.schemaVersion = 1,
  });
  final String id, inspectionId, alarmType, otherDescription, result, comments;
  final String? invalidatedBy, invalidationReason;
  final int attemptNumber, schemaVersion;
  final bool generated, detectedLocally, reported, acknowledged;
  final int? latencyMs;
  final DateTime? generatedAt, detectedAt, reportedAt, acknowledgedAt;
  final DateTime? invalidatedAt, updatedAt;
  final DateTime createdAt;
  final List<String> photoIds;
  bool get valid => invalidatedAt == null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'inspectionId': inspectionId,
    'alarmType': alarmType,
    'otherDescription': otherDescription,
    'attemptNumber': attemptNumber,
    'generated': generated,
    'detectedLocally': detectedLocally,
    'reported': reported,
    'generatedAt': generatedAt?.toUtc().toIso8601String(),
    'detectedAt': detectedAt?.toUtc().toIso8601String(),
    'reportedAt': reportedAt?.toUtc().toIso8601String(),
    'acknowledgedAt': acknowledgedAt?.toUtc().toIso8601String(),
    'latencyMs': latencyMs,
    'acknowledged': acknowledged,
    'result': result,
    'comments': comments,
    'photoIds': photoIds,
    'invalidatedAt': invalidatedAt?.toUtc().toIso8601String(),
    'invalidatedBy': invalidatedBy,
    'invalidationReason': invalidationReason,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory AlarmAttemptRecord.fromJson(Map<String, dynamic> json) =>
      AlarmAttemptRecord(
        id: json['id'] as String? ?? '',
        inspectionId: json['inspectionId'] as String? ?? '',
        alarmType: json['alarmType'] as String? ?? '',
        otherDescription: json['otherDescription'] as String? ?? '',
        attemptNumber: json['attemptNumber'] as int? ?? 1,
        generated: json['generated'] as bool? ?? false,
        detectedLocally: json['detectedLocally'] as bool? ?? false,
        reported: json['reported'] as bool? ?? false,
        generatedAt: _nullableDate(json['generatedAt']),
        detectedAt: _nullableDate(json['detectedAt']),
        reportedAt: _nullableDate(json['reportedAt']),
        acknowledgedAt: _nullableDate(json['acknowledgedAt']),
        latencyMs: json['latencyMs'] as int?,
        acknowledged: json['acknowledged'] as bool? ?? false,
        result: json['result'] as String? ?? '',
        comments: json['comments'] as String? ?? '',
        photoIds: _strings(json['photoIds']),
        invalidatedAt: _nullableDate(json['invalidatedAt']),
        invalidatedBy: json['invalidatedBy'] as String?,
        invalidationReason: json['invalidationReason'] as String?,
        createdAt: _date(json['createdAt']),
        updatedAt: _nullableDate(json['updatedAt']),
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );
}

class InstrumentSnapshot {
  const InstrumentSnapshot({
    required this.instrumentId,
    required this.type,
    required this.assetCode,
    required this.brandText,
    required this.modelText,
    required this.serialNumber,
    required this.measurementRange,
    required this.unit,
    required this.accuracyClass,
    required this.calibrationStatus,
    required this.calibrationCertificate,
    required this.condition,
    required this.capturedAt,
    this.schemaVersion = 1,
  });
  final String instrumentId, type, assetCode, brandText, modelText;
  final String serialNumber, measurementRange, unit, accuracyClass;
  final String calibrationStatus, calibrationCertificate, condition;
  final DateTime capturedAt;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'instrumentId': instrumentId,
    'type': type,
    'assetCode': assetCode,
    'brandText': brandText,
    'modelText': modelText,
    'serialNumber': serialNumber,
    'measurementRange': measurementRange,
    'unit': unit,
    'accuracyClass': accuracyClass,
    'calibrationStatus': calibrationStatus,
    'calibrationCertificate': calibrationCertificate,
    'condition': condition,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
}

List<String> _strings(Object? raw) =>
    (raw as List? ?? const []).map((value) => '$value').toList();
DateTime _date(Object? raw) =>
    DateTime.tryParse(raw as String? ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
DateTime? _nullableDate(Object? raw) =>
    DateTime.tryParse(raw as String? ?? '')?.toUtc();
