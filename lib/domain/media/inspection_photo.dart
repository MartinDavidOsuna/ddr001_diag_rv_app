import 'media_sync_status.dart';

enum PhotoSource { camera, deviceLibrary }

class InspectionPhoto {
  const InspectionPhoto({
    required this.id,
    required this.hydrantId,
    required this.inspectionId,
    this.inspectionType = 'f02A',
    required this.category,
    this.topic = '',
    this.testId,
    this.componentId,
    this.instrumentId,
    this.measurementSeriesId,
    this.measurementReadingId,
    this.evidenceRequirementId,
    required this.source,
    required this.originalFilename,
    required this.normalizedFilename,
    required this.localPath,
    required this.thumbnailPath,
    required this.mimeType,
    required this.fileSize,
    required this.width,
    required this.height,
    required this.sha256,
    this.processingProfileVersion = 'f02a-jpeg-v1',
    required this.capturedAt,
    required this.capturedByUserId,
    required this.capturedByName,
    required this.brigadeId,
    required this.deviceId,
    this.latitude,
    this.longitude,
    this.horizontalAccuracy,
    this.comment = '',
    this.syncStatus = MediaSyncStatus.pendingUpload,
    this.uploadAttempts = 0,
    this.uploadedAt,
    this.verifiedAt,
    this.remoteObjectKey,
    this.remoteSha256,
    this.remoteFileSize,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
    this.deletedAt,
  });
  final String id,
      hydrantId,
      inspectionId,
      inspectionType,
      category,
      topic,
      originalFilename,
      normalizedFilename,
      localPath,
      thumbnailPath,
      mimeType,
      sha256,
      processingProfileVersion,
      capturedByUserId,
      capturedByName,
      brigadeId,
      deviceId,
      comment;
  final String? testId,
      componentId,
      instrumentId,
      measurementSeriesId,
      measurementReadingId,
      evidenceRequirementId;
  final PhotoSource source;
  final int fileSize, width, height, uploadAttempts, schemaVersion;
  final double? latitude, longitude, horizontalAccuracy;
  final DateTime capturedAt, createdAt, updatedAt;
  final DateTime? uploadedAt, verifiedAt, deletedAt;
  final String? remoteObjectKey, remoteSha256, lastError;
  final int? remoteFileSize;
  final MediaSyncStatus syncStatus;
  bool get isSynchronized => syncStatus.isSynchronized;
  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hydrantId': hydrantId,
    'inspectionId': inspectionId,
    'inspectionType': inspectionType,
    'category': category,
    'topic': topic,
    'testId': testId,
    'componentId': componentId,
    'instrumentId': instrumentId,
    'measurementSeriesId': measurementSeriesId,
    'measurementReadingId': measurementReadingId,
    'evidenceRequirementId': evidenceRequirementId,
    'source': source.name,
    'originalFilename': originalFilename,
    'normalizedFilename': normalizedFilename,
    'localPath': localPath,
    'thumbnailPath': thumbnailPath,
    'mimeType': mimeType,
    'fileSize': fileSize,
    'width': width,
    'height': height,
    'sha256': sha256,
    'processingProfileVersion': processingProfileVersion,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'capturedByUserId': capturedByUserId,
    'capturedByName': capturedByName,
    'brigadeId': brigadeId,
    'deviceId': deviceId,
    'latitude': latitude,
    'longitude': longitude,
    'horizontalAccuracy': horizontalAccuracy,
    'comment': comment,
    'syncStatus': syncStatus.name,
    'uploadAttempts': uploadAttempts,
    'uploadedAt': uploadedAt?.toUtc().toIso8601String(),
    'verifiedAt': verifiedAt?.toUtc().toIso8601String(),
    'remoteObjectKey': remoteObjectKey,
    'remoteSha256': remoteSha256,
    'remoteFileSize': remoteFileSize,
    'lastError': lastError,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory InspectionPhoto.fromJson(Map<String, dynamic> j) => InspectionPhoto(
    id: j['id'] as String,
    hydrantId: j['hydrantId'] as String,
    inspectionId: j['inspectionId'] as String,
    inspectionType: j['inspectionType'] as String? ?? 'f02A',
    category: j['category'] as String? ?? 'otro',
    topic: j['topic'] as String? ?? '',
    testId: j['testId'] as String?,
    componentId: j['componentId'] as String?,
    instrumentId: j['instrumentId'] as String?,
    measurementSeriesId: j['measurementSeriesId'] as String?,
    measurementReadingId: j['measurementReadingId'] as String?,
    evidenceRequirementId: j['evidenceRequirementId'] as String?,
    source: _enum(PhotoSource.values, j['source'], PhotoSource.camera),
    originalFilename: j['originalFilename'] as String? ?? '',
    normalizedFilename: j['normalizedFilename'] as String? ?? '',
    localPath: j['localPath'] as String,
    thumbnailPath: j['thumbnailPath'] as String,
    mimeType: j['mimeType'] as String? ?? 'image/jpeg',
    fileSize: j['fileSize'] as int? ?? 0,
    width: j['width'] as int? ?? 0,
    height: j['height'] as int? ?? 0,
    sha256: j['sha256'] as String? ?? '',
    processingProfileVersion:
        j['processingProfileVersion'] as String? ?? 'f02a-jpeg-v1',
    capturedAt: _date(j['capturedAt']),
    capturedByUserId: j['capturedByUserId'] as String? ?? '',
    capturedByName: j['capturedByName'] as String? ?? '',
    brigadeId: j['brigadeId'] as String? ?? '',
    deviceId: j['deviceId'] as String? ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    horizontalAccuracy: (j['horizontalAccuracy'] as num?)?.toDouble(),
    comment: j['comment'] as String? ?? '',
    syncStatus: _enum(
      MediaSyncStatus.values,
      j['syncStatus'],
      MediaSyncStatus.pendingUpload,
    ),
    uploadAttempts: j['uploadAttempts'] as int? ?? 0,
    uploadedAt: DateTime.tryParse(j['uploadedAt'] as String? ?? '')?.toUtc(),
    verifiedAt: DateTime.tryParse(j['verifiedAt'] as String? ?? '')?.toUtc(),
    remoteObjectKey: j['remoteObjectKey'] as String?,
    remoteSha256: j['remoteSha256'] as String?,
    remoteFileSize: j['remoteFileSize'] as int?,
    lastError: j['lastError'] as String?,
    createdAt: _date(j['createdAt']),
    updatedAt: _date(j['updatedAt']),
    schemaVersion: j['schemaVersion'] as int? ?? 1,
    deletedAt: DateTime.tryParse(j['deletedAt'] as String? ?? '')?.toUtc(),
  );
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime _date(Object? value) =>
    DateTime.tryParse(value as String? ?? '')?.toUtc() ??
    DateTime.now().toUtc();
