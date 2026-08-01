import '../../checklist/data/checklist_models.dart';
import 'rv_sync_state.dart';
import 'parcel_valve_configuration.dart';

const requiredRvPhotoSlots = <String>[
  'front_closed',
  'left_side',
  'right_side',
  'back',
  'top',
  'front_open',
  'serial_plate',
];

const rvPhotoSlotLabels = <String, String>{
  'front_closed': 'Frente cerrado',
  'left_side': 'Lado izquierdo',
  'right_side': 'Lado derecho',
  'back': 'Parte posterior',
  'top': 'Parte superior',
  'front_open': 'Frente abierto',
  'serial_plate': 'Placa o número de serie',
};

class RvAnswer {
  const RvAnswer({
    required this.questionId,
    required this.sectionId,
    required this.answerType,
    required this.updatedAt,
    this.value,
    this.selectedOptions = const [],
    this.notApplicable = false,
    this.comment = '',
  });
  final String questionId, sectionId, answerType, comment;
  final Object? value;
  final List<Object?> selectedOptions;
  final bool notApplicable;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'sectionId': sectionId,
    'answerType': answerType,
    'value': value,
    'selectedOptions': selectedOptions,
    'notApplicable': notApplicable,
    'comment': comment,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory RvAnswer.fromJson(Map<String, dynamic> json) => RvAnswer(
    questionId: json['questionId'] as String,
    sectionId: json['sectionId'] as String,
    answerType: json['answerType'] as String,
    value: json['value'],
    selectedOptions: List<Object?>.from(
      json['selectedOptions'] as List? ?? const [],
    ),
    notApplicable: json['notApplicable'] as bool? ?? false,
    comment: json['comment'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
  );
}

class RvLocationSample {
  const RvLocationSample({
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.capturedAt,
    this.altitude,
    this.horizontalAccuracy,
    this.verticalAccuracy,
  });
  final double latitude, longitude;
  final double? altitude, horizontalAccuracy, verticalAccuracy;
  final String source;
  final DateTime capturedAt;
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'horizontalAccuracy': horizontalAccuracy,
    'verticalAccuracy': verticalAccuracy,
    'source': source,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };
  factory RvLocationSample.fromJson(Map<String, dynamic> json) =>
      RvLocationSample(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble(),
        horizontalAccuracy: (json['horizontalAccuracy'] as num?)?.toDouble(),
        verticalAccuracy: (json['verticalAccuracy'] as num?)?.toDouble(),
        source: json['source'] as String? ?? 'gps',
        capturedAt: DateTime.parse(json['capturedAt'] as String).toUtc(),
      );
}

class RvSignalSample {
  const RvSignalSample({
    required this.generation,
    required this.connected,
    required this.capturedAt,
    this.networkType,
    this.operatorName,
    this.dbm,
    this.level,
    this.roaming,
    this.transportType,
    this.networkTechnology,
    this.networkTypeRaw,
    this.overrideNetworkTypeRaw,
    this.signalPercent,
    this.asu,
    this.signalSource,
    this.subscriptionSlot,
    this.subscriptionCount,
    this.availabilityReason,
    this.isDefaultDataSubscription,
  });
  final String generation;
  final bool connected;
  final DateTime capturedAt;
  final String? networkType, operatorName;
  final int? dbm, level;
  final bool? roaming;
  final String? transportType;
  final String? networkTechnology;
  final String? networkTypeRaw;
  final String? overrideNetworkTypeRaw;
  final int? signalPercent;
  final int? asu;
  final String? signalSource;
  final int? subscriptionSlot;
  final int? subscriptionCount;
  final String? availabilityReason;
  final bool? isDefaultDataSubscription;
  Map<String, dynamic> toJson() => {
    'generation': generation,
    'connected': connected,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'networkType': networkType,
    'operator': operatorName,
    'dbm': dbm,
    'level': level,
    'roaming': roaming,
    'transportType': transportType,
    'networkTechnology': networkTechnology,
    'networkTypeRaw': networkTypeRaw,
    'overrideNetworkTypeRaw': overrideNetworkTypeRaw,
    'signalPercent': signalPercent,
    'signalAsu': asu,
    'signalSource': signalSource,
    'subscriptionSlot': subscriptionSlot,
    'subscriptionCount': subscriptionCount,
    'availabilityReason': availabilityReason,
    'isDefaultDataSubscription': isDefaultDataSubscription,
    'technicalData': {
      'transportType': transportType,
      'networkTechnology': networkTechnology,
      'networkTypeRaw': networkTypeRaw,
      'overrideNetworkTypeRaw': overrideNetworkTypeRaw,
      'signalPercent': signalPercent,
      'signalAsu': asu,
      'signalSource': signalSource,
      'subscriptionSlot': subscriptionSlot,
      'subscriptionCount': subscriptionCount,
      'availabilityReason': availabilityReason,
      'isDefaultDataSubscription': isDefaultDataSubscription,
    },
  };
  factory RvSignalSample.fromJson(Map<String, dynamic> json) => RvSignalSample(
    generation: json['generation'] as String? ?? 'UNKNOWN',
    connected: json['connected'] as bool? ?? false,
    capturedAt: DateTime.parse(json['capturedAt'] as String).toUtc(),
    networkType: json['networkType'] as String?,
    operatorName: json['operator'] as String?,
    dbm: json['dbm'] as int?,
    level: json['level'] as int?,
    roaming: json['roaming'] as bool?,
    transportType: json['transportType'] as String?,
    networkTechnology: json['networkTechnology'] as String?,
    networkTypeRaw: json['networkTypeRaw'] as String?,
    overrideNetworkTypeRaw: json['overrideNetworkTypeRaw'] as String?,
    signalPercent: json['signalPercent'] as int?,
    asu: json['signalAsu'] as int?,
    signalSource: json['signalSource'] as String?,
    subscriptionSlot: json['subscriptionSlot'] as int?,
    subscriptionCount: json['subscriptionCount'] as int?,
    availabilityReason: json['availabilityReason'] as String?,
    isDefaultDataSubscription: json['isDefaultDataSubscription'] as bool?,
  );

  factory RvSignalSample.fromNative(
    Map<String, dynamic> json, {
    required String fallbackTransport,
    required bool connected,
  }) {
    final technology = json['networkTechnology'] as String?;
    final generation = switch (technology) {
      '2G' => '2G',
      '3G' => '3G',
      'LTE' || '4G' => '4G',
      '5G SA' || '5G NSA' || '5G' => '5G',
      _ => connected ? 'UNKNOWN' : 'NONE',
    };
    return RvSignalSample(
      generation: generation,
      connected: connected,
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      networkType: json['networkTypeRaw'] as String?,
      operatorName: json['carrierName'] as String?,
      dbm: json['signalDbm'] as int?,
      level: json['signalLevel'] as int?,
      roaming: json['isRoaming'] as bool?,
      transportType: json['transportType'] as String? ?? fallbackTransport,
      networkTechnology: technology,
      networkTypeRaw: json['networkTypeRaw'] as String?,
      overrideNetworkTypeRaw: json['overrideNetworkTypeRaw'] as String?,
      signalPercent: json['signalPercent'] as int?,
      asu: json['signalAsu'] as int?,
      signalSource: json['signalSource'] as String?,
      subscriptionSlot: json['subscriptionSlot'] as int?,
      subscriptionCount: json['subscriptionCount'] as int?,
      availabilityReason: json['availabilityReason'] as String?,
      isDefaultDataSubscription: json['isDefaultDataSubscription'] as bool?,
    );
  }
}

class RvPhotoReference {
  const RvPhotoReference({
    required this.photoId,
    required this.slotCode,
    required this.status,
    this.serverPhotoId,
    this.retryCount = 0,
    this.lastError,
  });
  final String photoId, slotCode;
  final RvPhotoUploadStatus status;
  final String? serverPhotoId, lastError;
  final int retryCount;
  Map<String, dynamic> toJson() => {
    'photoId': photoId,
    'slotCode': slotCode,
    'status': status.name,
    'serverPhotoId': serverPhotoId,
    'retryCount': retryCount,
    'lastError': lastError,
  };
  factory RvPhotoReference.fromJson(Map<String, dynamic> json) =>
      RvPhotoReference(
        photoId: json['photoId'] as String,
        slotCode: json['slotCode'] as String,
        status: RvPhotoUploadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => RvPhotoUploadStatus.pending,
        ),
        serverPhotoId: json['serverPhotoId'] as String?,
        retryCount: json['retryCount'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );
}

class RvDraft {
  const RvDraft({
    required this.clientInspectionId,
    required this.hydrantId,
    required this.accountNumber,
    required this.fieldSessionId,
    required this.checklistId,
    required this.checklistVersion,
    required this.checklistSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.serverInspectionId,
    this.officialInspectionId,
    this.conflictId,
    this.lastStatusChangedAt,
    this.localStatus = RvLocalStatus.pendingCreate,
    this.remoteStatus = 'not_created',
    this.answersStatus = RvPartStatus.pending,
    this.locationStatus = RvPartStatus.notCaptured,
    this.signalStatus = RvPartStatus.notCaptured,
    this.photosStatus = RvPartStatus.notCaptured,
    this.submitStatus = RvPartStatus.notCaptured,
    this.answers = const {},
    this.location,
    this.signal,
    this.photos = const {},
    this.lastSyncError,
    this.retryCount = 0,
    this.activeFormStep = 0,
    this.parcelValveConfiguration,
    this.navigationQuestionId,
    this.navigationSubItemId,
    this.navigationFieldId,
    this.returnToSummary = false,
    this.currentStep = RvSyncStep.create,
    this.lastAttemptAt,
    this.nextRetryAt,
  });
  final String clientInspectionId,
      hydrantId,
      accountNumber,
      fieldSessionId,
      checklistId;
  final String? serverInspectionId,
      officialInspectionId,
      conflictId,
      lastSyncError;
  final int checklistVersion, retryCount, activeFormStep;
  final Map<String, dynamic> checklistSnapshot;
  final DateTime createdAt, updatedAt;
  final DateTime? lastAttemptAt, nextRetryAt, lastStatusChangedAt;
  final RvLocalStatus localStatus;
  final String remoteStatus;
  final RvPartStatus answersStatus,
      locationStatus,
      signalStatus,
      photosStatus,
      submitStatus;
  final Map<String, RvAnswer> answers;
  final RvLocationSample? location;
  final RvSignalSample? signal;
  final Map<String, List<RvPhotoReference>> photos;
  final RvSyncStep currentStep;
  final ParcelValveConfiguration? parcelValveConfiguration;
  final String? navigationQuestionId, navigationSubItemId, navigationFieldId;
  final bool returnToSummary;

  DynamicChecklist get checklist =>
      DynamicChecklist.fromJson(checklistSnapshot);
  bool get isReadOnly =>
      localStatus == RvLocalStatus.submitted ||
      localStatus == RvLocalStatus.conflict ||
      localStatus == RvLocalStatus.cancelled;
  int get photoCount =>
      photos.values.fold(0, (sum, values) => sum + values.length);
  List<RvPhotoReference> photosFor(String slot) =>
      List.unmodifiable(photos[slot] ?? const []);
  bool get hasAllPhotoSlots =>
      requiredRvPhotoSlots.every((slot) => photosFor(slot).isNotEmpty);
  bool get photosVerified => requiredRvPhotoSlots.every(
    (slot) => photosFor(
      slot,
    ).any((photo) => photo.status == RvPhotoUploadStatus.verified),
  );

  RvDraft copyWith({
    String? serverInspectionId,
    String? officialInspectionId,
    String? conflictId,
    DateTime? lastStatusChangedAt,
    RvLocalStatus? localStatus,
    String? remoteStatus,
    RvPartStatus? answersStatus,
    RvPartStatus? locationStatus,
    RvPartStatus? signalStatus,
    RvPartStatus? photosStatus,
    RvPartStatus? submitStatus,
    Map<String, RvAnswer>? answers,
    RvLocationSample? location,
    RvSignalSample? signal,
    Map<String, List<RvPhotoReference>>? photos,
    String? lastSyncError,
    bool clearError = false,
    int? retryCount,
    int? activeFormStep,
    ParcelValveConfiguration? parcelValveConfiguration,
    bool clearParcelValveConfiguration = false,
    String? navigationQuestionId,
    String? navigationSubItemId,
    String? navigationFieldId,
    bool clearNavigationTarget = false,
    bool? returnToSummary,
    RvSyncStep? currentStep,
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    DateTime? updatedAt,
  }) => RvDraft(
    clientInspectionId: clientInspectionId,
    serverInspectionId: serverInspectionId ?? this.serverInspectionId,
    officialInspectionId: officialInspectionId ?? this.officialInspectionId,
    conflictId: conflictId ?? this.conflictId,
    lastStatusChangedAt: lastStatusChangedAt ?? this.lastStatusChangedAt,
    hydrantId: hydrantId,
    accountNumber: accountNumber,
    fieldSessionId: fieldSessionId,
    checklistId: checklistId,
    checklistVersion: checklistVersion,
    checklistSnapshot: checklistSnapshot,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    localStatus: localStatus ?? this.localStatus,
    remoteStatus: remoteStatus ?? this.remoteStatus,
    answersStatus: answersStatus ?? this.answersStatus,
    locationStatus: locationStatus ?? this.locationStatus,
    signalStatus: signalStatus ?? this.signalStatus,
    photosStatus: photosStatus ?? this.photosStatus,
    submitStatus: submitStatus ?? this.submitStatus,
    answers: answers ?? this.answers,
    location: location ?? this.location,
    signal: signal ?? this.signal,
    photos: photos ?? this.photos,
    lastSyncError: clearError ? null : (lastSyncError ?? this.lastSyncError),
    retryCount: retryCount ?? this.retryCount,
    activeFormStep: activeFormStep ?? this.activeFormStep,
    parcelValveConfiguration: clearParcelValveConfiguration
        ? null
        : (parcelValveConfiguration ?? this.parcelValveConfiguration),
    navigationQuestionId: clearNavigationTarget
        ? null
        : (navigationQuestionId ?? this.navigationQuestionId),
    navigationSubItemId: clearNavigationTarget
        ? null
        : (navigationSubItemId ?? this.navigationSubItemId),
    navigationFieldId: clearNavigationTarget
        ? null
        : (navigationFieldId ?? this.navigationFieldId),
    returnToSummary: returnToSummary ?? this.returnToSummary,
    currentStep: currentStep ?? this.currentStep,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
  );

  Map<String, dynamic> toJson() => {
    'clientInspectionId': clientInspectionId,
    'serverInspectionId': serverInspectionId,
    'officialInspectionId': officialInspectionId,
    'conflictId': conflictId,
    'lastStatusChangedAt': lastStatusChangedAt?.toUtc().toIso8601String(),
    'hydrantId': hydrantId,
    'accountNumber': accountNumber,
    'fieldSessionId': fieldSessionId,
    'checklistId': checklistId,
    'checklistVersion': checklistVersion,
    'checklistSnapshot': checklistSnapshot,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'localStatus': localStatus.name,
    'remoteStatus': remoteStatus,
    'answersStatus': answersStatus.name,
    'locationStatus': locationStatus.name,
    'signalStatus': signalStatus.name,
    'photosStatus': photosStatus.name,
    'submitStatus': submitStatus.name,
    'answers': {for (final e in answers.entries) e.key: e.value.toJson()},
    'location': location?.toJson(),
    'signal': signal?.toJson(),
    'photos': {
      for (final e in photos.entries)
        e.key: e.value.map((photo) => photo.toJson()).toList(),
    },
    'lastSyncError': lastSyncError,
    'retryCount': retryCount,
    'activeFormStep': activeFormStep,
    'parcelValveConfiguration': parcelValveConfiguration?.toJson(),
    'navigationQuestionId': navigationQuestionId,
    'navigationSubItemId': navigationSubItemId,
    'navigationFieldId': navigationFieldId,
    'returnToSummary': returnToSummary,
    'currentStep': currentStep.name,
    'lastAttemptAt': lastAttemptAt?.toUtc().toIso8601String(),
    'nextRetryAt': nextRetryAt?.toUtc().toIso8601String(),
  };

  factory RvDraft.fromJson(Map<String, dynamic> json) => RvDraft(
    clientInspectionId: json['clientInspectionId'] as String,
    serverInspectionId: json['serverInspectionId'] as String?,
    officialInspectionId: json['officialInspectionId'] as String?,
    conflictId: json['conflictId'] as String?,
    lastStatusChangedAt: DateTime.tryParse(
      json['lastStatusChangedAt'] as String? ?? '',
    )?.toUtc(),
    hydrantId: json['hydrantId'] as String,
    accountNumber: json['accountNumber'] as String,
    fieldSessionId: json['fieldSessionId'] as String,
    checklistId: json['checklistId'] as String,
    checklistVersion: json['checklistVersion'] as int,
    checklistSnapshot: Map<String, dynamic>.from(
      json['checklistSnapshot'] as Map,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    localStatus: _enum(
      RvLocalStatus.values,
      json['localStatus'],
      RvLocalStatus.draft,
    ),
    remoteStatus: json['remoteStatus'] as String? ?? 'not_created',
    answersStatus: _enum(
      RvPartStatus.values,
      json['answersStatus'],
      RvPartStatus.pending,
    ),
    locationStatus: _enum(
      RvPartStatus.values,
      json['locationStatus'],
      RvPartStatus.notCaptured,
    ),
    signalStatus: _enum(
      RvPartStatus.values,
      json['signalStatus'],
      RvPartStatus.notCaptured,
    ),
    photosStatus: _enum(
      RvPartStatus.values,
      json['photosStatus'],
      RvPartStatus.notCaptured,
    ),
    submitStatus: _enum(
      RvPartStatus.values,
      json['submitStatus'],
      RvPartStatus.notCaptured,
    ),
    answers: {
      for (final entry in Map<String, dynamic>.from(
        json['answers'] as Map? ?? const {},
      ).entries)
        entry.key: RvAnswer.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        ),
    },
    location: json['location'] is Map
        ? RvLocationSample.fromJson(
            Map<String, dynamic>.from(json['location'] as Map),
          )
        : null,
    signal: json['signal'] is Map
        ? RvSignalSample.fromJson(
            Map<String, dynamic>.from(json['signal'] as Map),
          )
        : null,
    photos: {
      for (final entry in Map<String, dynamic>.from(
        json['photos'] as Map? ?? const {},
      ).entries)
        entry.key: entry.value is List
            ? [
                for (final value in entry.value as List)
                  RvPhotoReference.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
              ]
            : [
                // Backward compatibility with drafts written before 12.5.1.
                RvPhotoReference.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
              ],
    },
    lastSyncError: json['lastSyncError'] as String?,
    retryCount: json['retryCount'] as int? ?? 0,
    activeFormStep: json['activeFormStep'] as int? ?? 0,
    parcelValveConfiguration: json['parcelValveConfiguration'] is Map
        ? ParcelValveConfiguration.fromJson(
            Map<String, dynamic>.from(json['parcelValveConfiguration'] as Map),
          )
        : null,
    navigationQuestionId: json['navigationQuestionId'] as String?,
    navigationSubItemId: json['navigationSubItemId'] as String?,
    navigationFieldId: json['navigationFieldId'] as String?,
    returnToSummary: json['returnToSummary'] as bool? ?? false,
    currentStep: _enum(
      RvSyncStep.values,
      json['currentStep'],
      RvSyncStep.create,
    ),
    lastAttemptAt: DateTime.tryParse(
      json['lastAttemptAt'] as String? ?? '',
    )?.toUtc(),
    nextRetryAt: DateTime.tryParse(
      json['nextRetryAt'] as String? ?? '',
    )?.toUtc(),
  );
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
