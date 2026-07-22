enum ComponentSource { preloaded, observed, confirmed, corrected }

class DamageRecord {
  const DamageRecord({
    required this.id,
    required this.hydrantId,
    required this.inspectionId,
    required this.category,
    required this.affectedComponent,
    required this.severity,
    this.comments = '',
    this.photoIds = const [],
    required this.createdAt,
    required this.createdBy,
    this.schemaVersion = 1,
  });
  final String id,
      hydrantId,
      inspectionId,
      category,
      affectedComponent,
      severity,
      comments,
      createdBy;
  final List<String> photoIds;
  final DateTime createdAt;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'hydrantId': hydrantId,
    'inspectionId': inspectionId,
    'category': category,
    'affectedComponent': affectedComponent,
    'severity': severity,
    'comments': comments,
    'photoIds': photoIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'createdBy': createdBy,
    'schemaVersion': schemaVersion,
  };
}

class HydrantComponent {
  const HydrantComponent({
    required this.id,
    required this.componentType,
    this.quantity = 1,
    this.diameter,
    this.brand,
    this.model,
    this.serial,
    this.condition,
    this.comments = '',
    this.source = ComponentSource.observed,
  });
  final String id, componentType, comments;
  final int quantity;
  final String? diameter, brand, model, serial, condition;
  final ComponentSource source;
  Map<String, dynamic> toJson() => {
    'id': id,
    'componentType': componentType,
    'quantity': quantity,
    'diameter': diameter,
    'brand': brand,
    'model': model,
    'serial': serial,
    'condition': condition,
    'comments': comments,
    'source': source.name,
  };
}

class HydrantConfiguration {
  const HydrantConfiguration({
    required this.id,
    required this.hydrantId,
    this.components = const [],
    required this.updatedAt,
    this.schemaVersion = 1,
  });
  final String id, hydrantId;
  final List<HydrantComponent> components;
  final DateTime updatedAt;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'hydrantId': hydrantId,
    'components': components.map((e) => e.toJson()).toList(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
  };
}

class LocalHydrantRecord {
  const LocalHydrantRecord({
    required this.id,
    required this.code,
    required this.source,
    required this.pendingValidation,
    required this.createdBy,
    required this.brigadeId,
    required this.deviceId,
    required this.createdAt,
    this.reason = '',
    this.workSelection = 'visualOnly',
    this.authorizationReason = '',
    this.pendingSupervisorValidation = false,
    this.latitude,
    this.longitude,
    this.schemaVersion = 1,
  });
  final String id, code, source, createdBy, brigadeId, deviceId, reason;
  final String workSelection, authorizationReason;
  final bool pendingSupervisorValidation;
  final bool pendingValidation;
  final DateTime createdAt;
  final double? latitude, longitude;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'source': source,
    'pendingValidation': pendingValidation,
    'createdBy': createdBy,
    'brigadeId': brigadeId,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'reason': reason,
    'workSelection': workSelection,
    'authorizationReason': authorizationReason,
    'pendingSupervisorValidation': pendingSupervisorValidation,
    'latitude': latitude,
    'longitude': longitude,
    'schemaVersion': schemaVersion,
  };
}
