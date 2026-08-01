import '../enums/app_enums.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.brigadeId,
    required this.brigadeName,
    required this.deviceId,
  });
  final String id, fullName, email, role, brigadeId, brigadeName, deviceId;
}

class InspectionSummary {
  const InspectionSummary({
    required this.type,
    required this.status,
    required this.progress,
  });
  final InspectionType type;
  final InspectionStatus status;
  final double progress;
}

class Hydrant {
  const Hydrant({
    required this.id,
    required this.code,
    required this.locality,
    required this.parcel,
    required this.priority,
    required this.access,
    required this.syncStatus,
    required this.f02a,
    required this.f02b,
    required this.latitude,
    required this.longitude,
    this.damageCount = 0,
    this.photoCount = 0,
    this.source = HydrantSource.assigned,
    this.rvStatus = 'available',
    this.officialInspectionId,
    this.lastStatusChangedAt,
    this.reviewedByName,
    this.reviewedByCrew,
    this.hasConflict = false,
    this.conflictCount = 0,
    this.availableForRv = true,
    this.currentRound = 1,
    this.requiredPhotosVerified = false,
    this.isActive = true,
  });
  final String id, code, locality, parcel;
  final PriorityLevel priority;
  final AccessType access;
  final SyncStatus syncStatus;
  final InspectionSummary f02a, f02b;
  final double latitude, longitude;
  final int damageCount, photoCount;
  final HydrantSource source;
  final String rvStatus;
  final String? officialInspectionId, reviewedByName, reviewedByCrew;
  final DateTime? lastStatusChangedAt;
  final bool hasConflict, availableForRv, requiredPhotosVerified, isActive;
  final int conflictCount, currentRound;

  String get displayShortId {
    final segments = code.split('-');
    if (segments.length < 2) return code;
    final candidate = segments.last.trim();
    return RegExp(r'^\d+$').hasMatch(candidate) ? candidate : code;
  }

  Hydrant copyWith({
    String? locality,
    String? parcel,
    PriorityLevel? priority,
    SyncStatus? syncStatus,
    HydrantSource? source,
    InspectionSummary? f02a,
    InspectionSummary? f02b,
  }) => Hydrant(
    id: id,
    code: code,
    locality: locality ?? this.locality,
    parcel: parcel ?? this.parcel,
    priority: priority ?? this.priority,
    access: access,
    syncStatus: syncStatus ?? this.syncStatus,
    f02a: f02a ?? this.f02a,
    f02b: f02b ?? this.f02b,
    latitude: latitude,
    longitude: longitude,
    damageCount: damageCount,
    photoCount: photoCount,
    source: source ?? this.source,
    rvStatus: rvStatus,
    officialInspectionId: officialInspectionId,
    lastStatusChangedAt: lastStatusChangedAt,
    reviewedByName: reviewedByName,
    reviewedByCrew: reviewedByCrew,
    hasConflict: hasConflict,
    conflictCount: conflictCount,
    availableForRv: availableForRv,
    currentRound: currentRound,
    requiredPhotosVerified: requiredPhotosVerified,
    isActive: isActive,
  );
}

class TraceEvent {
  const TraceEvent({
    required this.id,
    required this.action,
    required this.description,
    required this.createdAt,
    required this.userId,
    required this.brigadeName,
    required this.deviceId,
    this.hydrantId,
    this.inspectionId,
    this.entityType,
    this.entityId,
    this.reason,
    this.metadata = const {},
    this.correlationId,
    this.schemaVersion = 1,
    this.syncStatus = SyncStatus.pending,
  });
  final String id, action, description, userId, brigadeName, deviceId;
  final String? hydrantId;
  final String? inspectionId, entityType, entityId, reason, correlationId;
  final Map<String, dynamic> metadata;
  final int schemaVersion;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'description': description,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'userId': userId,
    'brigadeName': brigadeName,
    'deviceId': deviceId,
    'hydrantId': hydrantId,
    'inspectionId': inspectionId,
    'entityType': entityType,
    'entityId': entityId,
    'reason': reason,
    'metadata': metadata,
    'correlationId': correlationId,
    'schemaVersion': schemaVersion,
    'syncStatus': syncStatus.name,
  };
}

class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.buildNumber,
    required this.title,
    required this.message,
    required this.status,
    this.isRequired = false,
    this.androidUrl = '',
    this.iosUrl,
    this.publishedAt,
    this.sha256,
    this.releaseNotes = const [],
  });
  final String latestVersion, minimumSupportedVersion, title, message;
  final int buildNumber;
  final UpdateStatus status;
  final bool isRequired;
  final String androidUrl;
  final String? iosUrl, sha256;
  final DateTime? publishedAt;
  final List<String> releaseNotes;
}
