import '../../../domain/enums/app_enums.dart';
import '../../../domain/models/app_models.dart';

class CachedHydrant {
  const CachedHydrant({
    required this.hydrantId,
    required this.accountNumber,
    required this.updatedAt,
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
  });

  final String hydrantId, accountNumber;
  final int? installationYear;
  final double? flowLps, sourceX, sourceY, latitude, longitude;
  final String? sourceCrs, locality, municipality, calculatedStatus;
  final Object? metadata;
  final DateTime updatedAt;

  factory CachedHydrant.fromApi(
    Map<String, dynamic> json,
    DateTime updatedAt,
  ) => CachedHydrant(
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
    updatedAt: updatedAt,
  );

  factory CachedHydrant.fromJson(Map<String, dynamic> json) => CachedHydrant(
    hydrantId: json['hydrantId'] as String,
    accountNumber: json['accountNumber'] as String,
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
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'hydrantId': hydrantId,
    'accountNumber': accountNumber,
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
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Hydrant toAppModel() {
    final status = switch (calculatedStatus) {
      'submitted' || 'validated' => InspectionStatus.completed,
      'in_progress' => InspectionStatus.inProgress,
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
      syncStatus: SyncStatus.synced,
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
    );
  }

  static double? _double(Object? value) =>
      value == null ? null : double.tryParse('$value');
  static int? _int(Object? value) =>
      value == null ? null : int.tryParse('$value');
}
