class VisualReport {
  const VisualReport({
    required this.id,
    required this.accountNumber,
    required this.versionNumber,
    required this.roundNumber,
    required this.status,
    required this.lastStatusChangedAt,
    required this.reviewer,
    required this.sections,
    required this.photos,
    this.location,
    this.signal,
    this.observations = const [],
    this.conflict,
    this.isValidated = false,
    this.isOwn = false,
    this.hasPendingChanges = false,
    this.syncStatus = 'synchronized',
  });
  final String id, accountNumber, status;
  final int versionNumber, roundNumber;
  final DateTime? lastStatusChangedAt;
  final ReportReviewer reviewer;
  final List<ReportSection> sections;
  final ReportPhotos photos;
  final ReportLocation? location;
  final ReportSignal? signal;
  final List<ReportObservation> observations;
  final ReportConflict? conflict;
  final bool isValidated, isOwn, hasPendingChanges;
  final String syncStatus;

  factory VisualReport.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) => VisualReport(
    id: '${json['visualReportId'] ?? ''}',
    accountNumber: '${json['accountNumber'] ?? 'No capturado'}',
    versionNumber: (json['versionNumber'] as num?)?.toInt() ?? 1,
    roundNumber: (json['rvRoundNumber'] as num?)?.toInt() ?? 1,
    status: '${json['status'] ?? 'submitted'}',
    syncStatus: '${json['syncStatus'] ?? 'synchronized'}',
    lastStatusChangedAt: DateTime.tryParse(
      '${json['lastStatusChangedAt'] ?? ''}',
    )?.toLocal(),
    reviewer: ReportReviewer.fromJson(
      Map<String, dynamic>.from(json['reviewer'] as Map? ?? const {}),
    ),
    sections: [
      for (final item in json['sections'] as List? ?? const [])
        ReportSection.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    photos: ReportPhotos.fromJson(
      Map<String, dynamic>.from(json['photos'] as Map? ?? const {}),
    ),
    location: json['location'] is Map
        ? ReportLocation.fromJson(
            Map<String, dynamic>.from(json['location'] as Map),
          )
        : null,
    signal: json['signal'] is Map
        ? ReportSignal.fromJson(
            Map<String, dynamic>.from(json['signal'] as Map),
          )
        : null,
    observations: [
      for (final item in json['observations'] as List? ?? const [])
        ReportObservation.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    conflict:
        json['conflict'] is Map &&
            (json['conflict'] as Map)['hasConflict'] == true
        ? ReportConflict.fromJson(
            Map<String, dynamic>.from(json['conflict'] as Map),
          )
        : null,
    isValidated: json['isValidated'] == true,
    isOwn:
        currentUserId != null &&
        '${(json['reviewer'] as Map?)?['userId']}' == currentUserId,
  );
}

class ReportReviewer {
  const ReportReviewer(this.userId, this.displayName, this.crewName);
  final String userId, displayName, crewName;
  factory ReportReviewer.fromJson(Map<String, dynamic> j) => ReportReviewer(
    '${j['userId'] ?? ''}',
    '${j['displayName'] ?? 'No capturado'}',
    '${j['crewName'] ?? 'No capturado'}',
  );
}

class ReportSection {
  const ReportSection(this.code, this.title, this.order, this.items);
  final String code, title;
  final int order;
  final List<ReportField> items;
  factory ReportSection.fromJson(Map<String, dynamic> j) => ReportSection(
    '${j['code'] ?? ''}',
    '${j['title'] ?? 'Sin título'}',
    (j['order'] as num?)?.toInt() ?? 0,
    [
      for (final x in j['items'] as List? ?? const [])
        ReportField.fromJson(Map<String, dynamic>.from(x as Map)),
    ],
  );
}

class ReportField {
  const ReportField(
    this.label,
    this.displayValue, {
    this.notes,
    this.unit,
    this.notApplicable = false,
  });
  final String label, displayValue;
  final String? notes, unit;
  final bool notApplicable;
  factory ReportField.fromJson(Map<String, dynamic> j) => ReportField(
    '${j['label'] ?? 'Campo'}',
    _safe(j['displayValue']),
    notes: j['notes']?.toString(),
    unit: j['unit']?.toString(),
    notApplicable: j['isNotApplicable'] == true,
  );
}

class ReportPhoto {
  const ReportPhoto({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.viewerUrl,
    this.description,
    this.available = true,
    this.integrityVerified = false,
  });
  final String id, title, thumbnailUrl, viewerUrl;
  final String? description;
  final bool available, integrityVerified;
  factory ReportPhoto.fromJson(Map<String, dynamic> j) => ReportPhoto(
    id: '${j['photoId'] ?? ''}',
    title: '${j['title'] ?? 'Fotografía'}',
    thumbnailUrl: '${j['thumbnailUrl'] ?? ''}',
    viewerUrl: '${j['viewerUrl'] ?? ''}',
    description: j['description']?.toString(),
    available: j['isAvailable'] != false,
    integrityVerified: j['integrityVerified'] == true,
  );
}

class ReportPhotos {
  const ReportPhotos(this.required, this.general);
  final List<ReportPhoto> required, general;
  factory ReportPhotos.fromJson(Map<String, dynamic> j) => ReportPhotos(
    [
      for (final x in j['required'] as List? ?? const [])
        ReportPhoto.fromJson(Map<String, dynamic>.from(x as Map)),
    ],
    [
      for (final x in j['general'] as List? ?? const [])
        ReportPhoto.fromJson(Map<String, dynamic>.from(x as Map)),
    ],
  );
  List<ReportPhoto> get all => [...required, ...general];
}

class ReportLocation {
  const ReportLocation(
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.source,
  );
  final String latitude, longitude, altitude, accuracy, source;
  factory ReportLocation.fromJson(Map<String, dynamic> j) => ReportLocation(
    _safe(j['latitude']),
    _safe(j['longitude']),
    _safe(j['altitude']),
    _safe(j['horizontalAccuracy']),
    _safe(j['source']),
  );
}

class ReportSignal {
  const ReportSignal(
    this.generation,
    this.networkType,
    this.carrier,
    this.dbm,
    this.connected,
  );
  final String generation, networkType, carrier, dbm, connected;
  factory ReportSignal.fromJson(Map<String, dynamic> j) => ReportSignal(
    _safe(j['generation']),
    _safe(j['networkType']),
    _safe(j['carrier']),
    _safe(j['dbm']),
    j['isConnected'] == null
        ? 'No capturado'
        : j['isConnected'] == true
        ? 'Sí'
        : 'No',
  );
}

class ReportObservation {
  const ReportObservation(this.text, this.actorType, this.createdAt);
  final String text, actorType;
  final DateTime? createdAt;
  factory ReportObservation.fromJson(Map<String, dynamic> j) =>
      ReportObservation(
        _safe(j['text']),
        '${j['actorType'] ?? 'system'}',
        DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal(),
      );
}

class ReportConflict {
  const ReportConflict(this.type, this.message);
  final String type, message;
  factory ReportConflict.fromJson(Map<String, dynamic> j) => ReportConflict(
    '${j['type'] ?? 'officiality_conflict'}',
    '${j['message'] ?? 'Existe un conflicto pendiente.'}',
  );
}

String _safe(Object? value) =>
    value == null || '$value'.trim().isEmpty || value == 'null'
    ? 'No capturado'
    : '$value';
