import '../../../domain/enums/app_enums.dart';
import '../../../domain/models/app_models.dart';

class CachedHydrant {
  const CachedHydrant({
    required this.hydrantId,
    required this.accountNumber,
    required this.updatedAt,
    this.scope = 'all',
    this.installationYear,
    this.flowLps,
    this.sourceX,
    this.sourceY,
    this.sourceCrs,
    this.latitude,
    this.longitude,
    this.locality,
    this.municipality,
    this.metadata,
    this.calculatedStatus,
    this.rvStatus,
    this.officialInspectionId,
    this.lastStatusChangedAt,
    this.reviewedByUserId,
    this.reviewedByName,
    this.reviewedByCrew,
    this.hasConflict = false,
    this.conflictCount = 0,
    this.availableForRv = true,
    this.currentRound = 1,
    this.requiredPhotosVerified = false,
    this.isActive = true,
    this.latestInspectionId,
    this.latestInspectionStatus,
    this.latestInspectionStartedAt,
    this.latestInspectionSubmittedAt,
    this.latestInspectionRevisionNumber,
    this.sectionCode,
    this.installationAngleDeg,
    this.elevationM,
    this.outletCount,
    this.source = 'remote',
    this.createdByUserId,
    this.accountId,
    this.environment,
    this.remoteId,
    this.reason,
  });

  final String hydrantId, accountNumber, scope;
  final int? installationYear, latestInspectionRevisionNumber, outletCount;
  final double? flowLps,
      sourceX,
      sourceY,
      latitude,
      longitude,
      installationAngleDeg,
      elevationM;
  final String? sourceCrs,
      locality,
      municipality,
      calculatedStatus,
      rvStatus,
      officialInspectionId,
      reviewedByUserId,
      reviewedByName,
      reviewedByCrew,
      latestInspectionId,
      latestInspectionStatus,
      sectionCode;
  final DateTime? latestInspectionStartedAt,
      latestInspectionSubmittedAt,
      lastStatusChangedAt;
  final bool hasConflict, availableForRv, requiredPhotosVerified, isActive;
  final int conflictCount, currentRound;
  final Object? metadata;
  final String source;
  final String? createdByUserId, accountId, environment, remoteId, reason;
  final DateTime updatedAt;

  factory CachedHydrant.fromApi(
    Map<String, dynamic> json,
    DateTime updatedAt, {
    String scope = 'all',
  }) => CachedHydrant(
    scope: scope,
    hydrantId: '${json['hydrant_id'] ?? json['hydrantId']}',
    accountNumber: '${json['account_number'] ?? json['accountNumber']}',
    installationYear: _int(json['installation_year']),
    flowLps: _double(json['flow_lps']),
    sourceX: _double(json['source_x']),
    sourceY: _double(json['source_y']),
    sourceCrs: json['source_crs']?.toString(),
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    locality: json['locality']?.toString(),
    municipality: json['municipality']?.toString(),
    metadata: json['metadata_json'],
    calculatedStatus: json['calculated_status']?.toString(),
    rvStatus: json['rvStatus']?.toString() ?? 'available',
    officialInspectionId: json['officialInspectionId']?.toString(),
    lastStatusChangedAt: _date(json['lastStatusChangedAt']),
    reviewedByUserId: json['reviewedByUserId']?.toString(),
    reviewedByName: json['reviewedByName']?.toString(),
    reviewedByCrew: json['reviewedByCrew']?.toString(),
    hasConflict: json['hasConflict'] == true,
    conflictCount: _int(json['conflictCount']) ?? 0,
    availableForRv: json['availableForRv'] is bool
        ? json['availableForRv'] as bool
        : true,
    currentRound: _int(json['currentRound']) ?? 1,
    requiredPhotosVerified: json['requiredPhotosVerified'] == true,
    isActive: json['isActive'] is bool ? json['isActive'] as bool : true,
    latestInspectionId: json['latestInspectionId']?.toString(),
    latestInspectionStatus: json['latestInspectionStatus']?.toString(),
    latestInspectionStartedAt: _date(json['latestInspectionStartedAt']),
    latestInspectionSubmittedAt: _date(json['latestInspectionSubmittedAt']),
    latestInspectionRevisionNumber: _int(
      json['latestInspectionRevisionNumber'],
    ),
    sectionCode: json['section_code']?.toString(),
    installationAngleDeg: _double(json['installation_angle_deg']),
    elevationM: _double(json['elevation_m']),
    outletCount: _int(json['outlet_count']),
    updatedAt: _date(json['updatedAt'] ?? json['updated_at']) ?? updatedAt,
    source: json['source_type']?.toString() == 'manual' ? 'manual' : 'remote',
    createdByUserId: json['created_by_user_id']?.toString(),
    environment: json['source_environment']?.toString(),
    remoteId: json['source_type']?.toString() == 'manual'
        ? '${json['hydrant_id'] ?? json['hydrantId']}'
        : null,
    reason: json['manual_reason']?.toString(),
  );

  factory CachedHydrant.fromJson(Map<String, dynamic> json) => CachedHydrant(
    hydrantId: json['hydrantId'] as String,
    accountNumber: json['accountNumber'] as String,
    scope: json['scope'] as String? ?? 'all',
    installationYear: _int(json['installationYear']),
    flowLps: _double(json['flowLps']),
    sourceX: _double(json['sourceX']),
    sourceY: _double(json['sourceY']),
    sourceCrs: json['sourceCrs'] as String?,
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    locality: json['locality'] as String?,
    municipality: json['municipality'] as String?,
    metadata: json['metadata'],
    calculatedStatus: json['calculatedStatus'] as String?,
    rvStatus: json['rvStatus'] as String? ?? 'available',
    officialInspectionId: json['officialInspectionId'] as String?,
    lastStatusChangedAt: _date(json['lastStatusChangedAt']),
    reviewedByUserId: json['reviewedByUserId'] as String?,
    reviewedByName: json['reviewedByName'] as String?,
    reviewedByCrew: json['reviewedByCrew'] as String?,
    hasConflict: json['hasConflict'] as bool? ?? false,
    conflictCount: _int(json['conflictCount']) ?? 0,
    availableForRv: json['availableForRv'] as bool? ?? true,
    currentRound: _int(json['currentRound']) ?? 1,
    requiredPhotosVerified: json['requiredPhotosVerified'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? true,
    latestInspectionId: json['latestInspectionId'] as String?,
    latestInspectionStatus: json['latestInspectionStatus'] as String?,
    latestInspectionStartedAt: _date(json['latestInspectionStartedAt']),
    latestInspectionSubmittedAt: _date(json['latestInspectionSubmittedAt']),
    latestInspectionRevisionNumber: _int(
      json['latestInspectionRevisionNumber'],
    ),
    sectionCode: json['sectionCode'] as String?,
    installationAngleDeg: _double(json['installationAngleDeg']),
    elevationM: _double(json['elevationM']),
    outletCount: _int(json['outletCount']),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    source: json['source'] as String? ?? 'remote',
    createdByUserId: json['createdByUserId'] as String?,
    accountId: json['accountId'] as String?,
    environment: json['environment'] as String?,
    remoteId: json['remoteId'] as String?,
    reason: json['reason'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'hydrantId': hydrantId,
    'accountNumber': accountNumber,
    'scope': scope,
    'installationYear': installationYear,
    'flowLps': flowLps,
    'sourceX': sourceX,
    'sourceY': sourceY,
    'sourceCrs': sourceCrs,
    'latitude': latitude,
    'longitude': longitude,
    'locality': locality,
    'municipality': municipality,
    'metadata': metadata,
    'calculatedStatus': calculatedStatus,
    'rvStatus': rvStatus,
    'officialInspectionId': officialInspectionId,
    'lastStatusChangedAt': lastStatusChangedAt?.toUtc().toIso8601String(),
    'reviewedByUserId': reviewedByUserId,
    'reviewedByName': reviewedByName,
    'reviewedByCrew': reviewedByCrew,
    'hasConflict': hasConflict,
    'conflictCount': conflictCount,
    'availableForRv': availableForRv,
    'currentRound': currentRound,
    'requiredPhotosVerified': requiredPhotosVerified,
    'isActive': isActive,
    'latestInspectionId': latestInspectionId,
    'latestInspectionStatus': latestInspectionStatus,
    'latestInspectionStartedAt': latestInspectionStartedAt
        ?.toUtc()
        .toIso8601String(),
    'latestInspectionSubmittedAt': latestInspectionSubmittedAt
        ?.toUtc()
        .toIso8601String(),
    'latestInspectionRevisionNumber': latestInspectionRevisionNumber,
    'sectionCode': sectionCode,
    'installationAngleDeg': installationAngleDeg,
    'elevationM': elevationM,
    'outletCount': outletCount,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'source': source,
    'createdByUserId': createdByUserId,
    'accountId': accountId,
    'environment': environment,
    'remoteId': remoteId,
    'reason': reason,
  };

  Hydrant toAppModel() {
    final status = switch (rvStatus ??
        latestInspectionStatus ??
        calculatedStatus) {
      'submitted' || 'completed' => InspectionStatus.completed,
      'validated' => InspectionStatus.validated,
      'returned' || 'rejected' => InspectionStatus.returned,
      'draft' || 'in_progress' || 'pending_sync' => InspectionStatus.inProgress,
      _ => InspectionStatus.pending,
    };
    return Hydrant(
      id: hydrantId,
      code: accountNumber,
      locality: locality?.isNotEmpty == true
          ? locality!
          : (municipality ?? 'Sin localidad'),
      parcel: municipality ?? 'Sin municipio',
      priority: PriorityLevel.medium,
      access: AccessType.both,
      syncStatus: source == 'manual' && remoteId == null
          ? SyncStatus.pending
          : SyncStatus.synced,
      f02a: InspectionSummary(
        type: InspectionType.f02A,
        status: status,
        progress: status == InspectionStatus.completed ? 1 : 0,
      ),
      f02b: const InspectionSummary(
        type: InspectionType.f02B,
        status: InspectionStatus.notRequired,
        progress: 0,
      ),
      latitude: latitude ?? 0,
      longitude: longitude ?? 0,
      source: source == 'manual'
          ? HydrantSource.fieldCreated
          : HydrantSource.assigned,
      rvStatus: rvStatus ?? 'available',
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

  static double? _double(Object? value) =>
      value == null ? null : double.tryParse('$value');
  static int? _int(Object? value) =>
      value == null ? null : int.tryParse('$value');
  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse('$value')?.toUtc();
}
