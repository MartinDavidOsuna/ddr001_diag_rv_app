import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/media/file_digest_service.dart';
import '../../../domain/media/inspection_photo.dart';
import '../../../domain/media/photo_integrity_status.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import '../domain/parcel_valve_configuration.dart';
import '../domain/rv_versioning.dart';

class RemoteInspection {
  const RemoteInspection({
    required this.id,
    required this.status,
    this.hydrantId,
    this.result,
    this.officialInspectionId,
    this.conflictId,
    this.rvStatus,
    this.lastStatusChangedAt,
    this.evidence,
  });
  final String id, status;
  final String? hydrantId, result, officialInspectionId, conflictId, rvStatus;
  final DateTime? lastStatusChangedAt;
  final RemoteCallEvidence? evidence;
}

class RemoteCallEvidence {
  const RemoteCallEvidence({
    required this.statusCode,
    required this.method,
    required this.logicalEndpoint,
    this.requestId,
  });

  final int statusCode;
  final String method;
  final String logicalEndpoint;
  final String? requestId;
}

class RemotePhoto {
  const RemotePhoto({
    required this.id,
    required this.slotCode,
    required this.status,
    this.sha256,
    this.clientSha256,
    this.evidence,
  });
  final String id, slotCode, status;
  final String? sha256, clientSha256;
  final RemoteCallEvidence? evidence;
}

class RemoteBatchResult<T> {
  const RemoteBatchResult(this.items, this.evidence);
  final List<T> items;
  final RemoteCallEvidence evidence;
}

class RemotePhotoIntegrity {
  const RemotePhotoIntegrity({
    required this.photoId,
    required this.status,
    required this.originalPresent,
    required this.thumbnailPresent,
    required this.storageVerified,
    required this.mapped,
    required this.mappingStatus,
    required this.retryable,
    required this.repairable,
    this.serverSha256,
  });

  final String photoId;
  final PhotoIntegrityStatus status;
  final bool originalPresent, thumbnailPresent, storageVerified, mapped;
  final PhotoMappingStatus mappingStatus;
  final bool retryable, repairable;
  final String? serverSha256;

  factory RemotePhotoIntegrity.fromJson(Map<String, dynamic> json) =>
      RemotePhotoIntegrity(
        photoId: '${json['photoId'] ?? ''}',
        status: _integrityStatusFromWire(json['status']),
        originalPresent: json['originalPresent'] == true,
        thumbnailPresent: json['thumbnailPresent'] == true,
        storageVerified: json['storageVerified'] == true,
        mapped: json['mapped'] == true,
        mappingStatus: photoMappingStatusFromWire(json['mappingStatus']),
        retryable: json['retryable'] == true,
        repairable: json['repairable'] == true,
        serverSha256: json['serverSha256']?.toString(),
      );
}

PhotoIntegrityStatus _integrityStatusFromWire(Object? value) =>
    switch (value?.toString()) {
      'confirmed' => PhotoIntegrityStatus.confirmed,
      'missing_original' => PhotoIntegrityStatus.missingOriginal,
      'missing_thumbnail' => PhotoIntegrityStatus.missingThumbnail,
      'hash_mismatch' => PhotoIntegrityStatus.hashMismatch,
      'missing_mapping' => PhotoIntegrityStatus.missingMapping,
      'mapping_conflict' => PhotoIntegrityStatus.mappingConflict,
      'deleted' => PhotoIntegrityStatus.deleted,
      'not_verified' => PhotoIntegrityStatus.notVerified,
      'not_found' => PhotoIntegrityStatus.notFound,
      _ => PhotoIntegrityStatus.retryRequired,
    };

class RemoteHydrantIdentity {
  const RemoteHydrantIdentity({required this.id, required this.accountNumber});
  final String id, accountNumber;
}

class InspectionRemoteRepository {
  InspectionRemoteRepository(
    this.client, {
    this._digestService = const StreamingFileDigestService(),
  });
  static const _androidFiles = MethodChannel(
    'com.aquafim.ddr001diag/app_files',
  );
  final ApiClient client;
  final FileDigestService _digestService;

  Future<({File source, File upload})> _preparePhotoPayload(
    File file,
    String photoId,
  ) async {
    if (Platform.isAndroid) {
      try {
        // Android stages a non-destructive cache copy and returns its small path
        // instead of transferring the complete image on the platform UI thread.
        final staged = await _androidFiles
            .invokeMapMethod<String, String>('stage', {
              'path': file.path,
              'photoId': photoId,
            })
            .timeout(const Duration(seconds: 30));
        final sourcePath = staged?['sourcePath'];
        final uploadPath = staged?['uploadPath'];
        if (sourcePath == null || uploadPath == null) {
          throw const ApiException(
            ApiErrorKind.invalidData,
            'Android no pudo preparar la fotografía local.',
          );
        }
        final source = File(sourcePath);
        final upload = File(uploadPath);
        if (!await source.exists() || !await upload.exists()) {
          throw const ApiException(
            ApiErrorKind.invalidData,
            'Android no conservó la representación de carga.',
          );
        }
        return (source: source, upload: upload);
      } on PlatformException catch (error) {
        throw ApiException(
          ApiErrorKind.invalidData,
          'Android no pudo preparar la fotografía local (${error.code}).',
        );
      } on TimeoutException {
        throw const ApiException(
          ApiErrorKind.invalidData,
          'La fotografía local permanece bloqueada y no pudo recuperarse.',
        );
      }
    }
    try {
      await file.openRead(0, 1).first.timeout(const Duration(seconds: 10));
      return (source: file, upload: file);
    } on TimeoutException {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'La fotografía local tardó demasiado en leerse.',
      );
    }
  }

  Future<RemoteHydrantIdentity?> findHydrantByAccount(String account) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/hydrants/${Uri.encodeComponent(account.trim())}',
      );
      final data = response.data ?? const {};
      final id = (data['hydrant_id'] ?? data['hydrantId'] ?? data['id'])
          ?.toString();
      final number = (data['account_number'] ?? data['accountNumber'])
          ?.toString();
      if (id == null || number == null) {
        throw const ApiException(
          ApiErrorKind.invalidData,
          'Respuesta de identidad de hidrante inválida.',
        );
      }
      return RemoteHydrantIdentity(id: id, accountNumber: number);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<RvVersionResult> createVersion(RvDraft draft) async {
    final reportId = draft.visualReportId;
    final baseVersionId = draft.baseVersionId ?? draft.currentVersionId;
    final clientVersionId = draft.pendingVersionClientId;
    if (reportId == null || baseVersionId == null || clientVersionId == null) {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'Faltan los identificadores de la versión base.',
      );
    }
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/visual-reports/$reportId/versions',
        data: {
          'baseVersionId': baseVersionId,
          'clientVersionId': clientVersionId,
          'changeReason': 'Edición móvil sincronizada',
          'snapshot': draft.toJson(),
          'technicalContentChanged': draft.canEditTechnical,
          'generalObservation': draft.generalObservations,
          'generalPhotos': [
            for (final photo in draft.generalPhotos)
              if (photo.status == RvPhotoUploadStatus.verified &&
                  photo.serverPhotoId != null)
                {
                  'photoId': photo.serverPhotoId,
                  'order':
                      photo.order ?? draft.generalPhotos.indexOf(photo) + 1,
                  'description': photo.description,
                },
          ],
        },
        options: Options(
          headers: {'Idempotency-Key': 'version-$clientVersionId'},
        ),
      );
      return RvVersionResult.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } on FormatException {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'Respuesta de versión inválida.',
      );
    }
  }

  Future<RemoteCallEvidence?> saveGeneralContent(RvDraft draft) async {
    final id = draft.serverInspectionId;
    if (id == null) return null;
    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '/inspections/$id/general-content',
        data: {
          'generalObservations': draft.generalObservations,
          'generalPhotos': [
            for (final photo in draft.generalPhotos)
              if (photo.status == RvPhotoUploadStatus.verified &&
                  photo.serverPhotoId != null)
                {
                  'photoId': photo.serverPhotoId,
                  'order':
                      photo.order ?? draft.generalPhotos.indexOf(photo) + 1,
                  'description': photo.description,
                },
          ],
        },
      );
      return _evidence(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteInspection> create(RvDraft draft) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections',
        data: {
          'clientInspectionId': draft.clientInspectionId,
          'accountNumber': draft.accountNumber,
        },
        options: Options(
          headers: {
            'Idempotency-Key': 'inspection-${draft.clientInspectionId}',
          },
        ),
      );
      return _inspection(
        response.data ?? const {},
        evidence: _evidence(response),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteInspection> get(String id) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/inspections/$id',
      );
      return _inspection(
        response.data ?? const {},
        evidence: _evidence(response),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteInspection?> findByClientInspectionId(String clientId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/inspections/by-client/${Uri.encodeComponent(clientId)}',
      );
      return _inspection(
        response.data ?? const {},
        evidence: _evidence(response),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteCallEvidence?> saveAnswers(
    String id,
    List<Map<String, dynamic>> answers,
    String key,
  ) async {
    if (answers.isEmpty) return null;
    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '/inspections/$id/answers',
        data: {'answers': answers},
        options: Options(headers: {'Idempotency-Key': key}),
      );
      return _evidence(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteCallEvidence> saveParcelValves(
    String id,
    ParcelValveConfiguration configuration,
  ) async {
    String remoteId(Map<String, dynamic>? value, String field) {
      if (value?['mode'] == 'illegible') return '';
      final id = value?['catalogId']?.toString();
      if (id == null || id.isEmpty) {
        throw ApiException(
          ApiErrorKind.validation,
          '$field está pendiente de sincronización.',
        );
      }
      return id;
    }

    String? brandId(Map<String, dynamic>? value, String field) =>
        value?['mode'] == 'illegible' ? null : remoteId(value, field);

    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '/inspections/$id/parcel-valves',
        data: {
          'configurationType': configuration.type.wireName,
          'customConfigurationText': configuration.customDescription,
          'valveCount': configuration.valveCount,
          'valves': [
            for (final valve in configuration.valves)
              {
                'index': valve.index,
                'diameterId': remoteId(valve.diameter, 'El diámetro'),
                'diameterDisplayValue': valve.diameter!['displayValue'],
                'valveBrandId': brandId(
                  valve.valveBrand,
                  'La marca de válvula',
                ),
                'valveBrandDisplayValue': valve.valveBrand!['displayValue'],
                'valveBrandReadability': valve.valveBrand == null
                    ? 'readable'
                    : (valve.valveBrand!['mode'] ?? 'readable'),
                'valveBrandIllegibleReason': valve.valveBrand == null
                    ? null
                    : valve.valveBrand!['reason'],
                'hasSolenoid': valve.hasSolenoid,
                'solenoidBrandId': valve.hasSolenoid
                    ? brandId(valve.solenoidBrand, 'La marca del solenoide')
                    : null,
                'solenoidBrandDisplayValue': valve.hasSolenoid
                    ? valve.solenoidBrand!['displayValue']
                    : null,
                'solenoidBrandReadability': valve.hasSolenoid
                    ? (valve.solenoidBrand!['mode'] ?? 'readable')
                    : null,
                'solenoidBrandIllegibleReason': valve.hasSolenoid
                    ? valve.solenoidBrand!['reason']
                    : null,
                'hasPilot': valve.hasPilot,
                'pilotConnected': valve.hasPilot ? valve.pilotConnected : null,
                'pilotBrandId': valve.hasPilot
                    ? brandId(valve.pilotBrand, 'La marca del piloto')
                    : null,
                'pilotBrandDisplayValue': valve.hasPilot
                    ? valve.pilotBrand!['displayValue']
                    : null,
                'pilotBrandReadability': valve.hasPilot
                    ? (valve.pilotBrand!['mode'] ?? 'readable')
                    : null,
                'pilotBrandIllegibleReason': valve.hasPilot
                    ? valve.pilotBrand!['reason']
                    : null,
                'hasPressureGauge': valve.hasPressureGauge,
                'pressureGaugeBrandId': valve.hasPressureGauge
                    ? brandId(
                        valve.pressureGaugeBrand,
                        'La marca del manómetro',
                      )
                    : null,
                'pressureGaugeBrandDisplayValue': valve.hasPressureGauge
                    ? valve.pressureGaugeBrand!['displayValue']
                    : null,
                'pressureGaugeBrandReadability': valve.hasPressureGauge
                    ? (valve.pressureGaugeBrand!['mode'] ?? 'readable')
                    : null,
                'pressureGaugeBrandIllegibleReason': valve.hasPressureGauge
                    ? valve.pressureGaugeBrand!['reason']
                    : null,
              },
          ],
        },
        options: Options(headers: {'Idempotency-Key': 'parcel-valves-$id'}),
      );
      return _evidence(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteCallEvidence> saveLocation(
    String id,
    RvLocationSample sample,
    String key,
  ) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/location-samples',
        data: sample.toJson(),
        options: Options(headers: {'Idempotency-Key': key}),
      );
      return _evidence(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteCallEvidence> saveSignal(
    String id,
    RvSignalSample sample,
    String key,
  ) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/signal-samples',
        data: sample.toJson(),
        options: Options(headers: {'Idempotency-Key': key}),
      );
      return _evidence(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemotePhoto> uploadPhoto(
    String id,
    String slotCode,
    InspectionPhoto photo,
  ) async {
    final file = File(photo.localPath);
    if (!await file.exists()) {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'El archivo de fotografía no existe.',
      );
    }
    try {
      // Each phase consumes bounded file chunks and releases its stream before
      // the next one starts. No complete JPEG is retained in the Dart heap.
      final payload = await _preparePhotoPayload(file, photo.id);
      if (await payload.source.length() == 0 ||
          await payload.upload.length() == 0) {
        throw const ApiException(
          ApiErrorKind.invalidData,
          'El archivo de fotografía está vacío.',
        );
      }
      final actualSha256 = await _digestService.sha256Of(payload.source);
      if (photo.sha256.isNotEmpty &&
          actualSha256.toLowerCase() != photo.sha256.toLowerCase()) {
        throw const ApiException(
          ApiErrorKind.invalidData,
          'La fotografía local no coincide con su huella de integridad.',
        );
      }
      final uploadSha256 = payload.upload.path == payload.source.path
          ? actualSha256
          : await _digestService.sha256Of(payload.upload);
      final multipart = await MultipartFile.fromFile(
        payload.upload.path,
        filename: photo.normalizedFilename,
      );
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/photos',
        data: FormData.fromMap({
          'photo': multipart,
          'photoId': photo.id,
          'slotCode': slotCode,
          'clientSha256': uploadSha256,
          'capturedAt': photo.capturedAt.toUtc().toIso8601String(),
          'metadata':
              '{"questionId":${photo.evidenceRequirementId == null ? 'null' : '"${photo.evidenceRequirementId}"'}}',
        }),
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final data = response.data ?? const {};
      return RemotePhoto(
        id: '${data['photoId'] ?? photo.id}',
        slotCode: '${data['slotCode'] ?? slotCode}',
        status: '${data['status'] ?? 'verified'}',
        sha256: (data['normalizedSha256'] ?? data['sha256'])?.toString(),
        evidence: _evidence(response),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<RemotePhoto>> photos(String id) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/inspections/$id/photos',
      );
      return (response.data?['items'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) {
            final data = Map<String, dynamic>.from(raw);
            return RemotePhoto(
              id: '${data['photo_id'] ?? data['photoId']}',
              slotCode: '${data['slot_code'] ?? data['slotCode']}',
              status: '${data['upload_status'] ?? data['status']}',
              sha256:
                  (data['normalized_sha256'] ??
                          data['server_sha256'] ??
                          data['sha256'])
                      ?.toString(),
              clientSha256: (data['client_sha256'] ?? data['clientSha256'])
                  ?.toString(),
            );
          })
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<RemotePhotoIntegrity>> verifyPhotosBatch(
    Iterable<String> photoIds,
  ) async {
    final unique = photoIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const [];
    if (unique.length > 100) {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'El lote de verificación supera 100 fotografías.',
      );
    }
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/photos/verify-batch',
        data: {'photoIds': unique},
      );
      return (response.data?['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                RemotePhotoIntegrity.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.photoId.isNotEmpty)
          .toList(growable: false);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteBatchResult<RemotePhotoIntegrity>> verifyPhotosBatchWithEvidence(
    Iterable<String> photoIds,
  ) async {
    final unique = photoIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'El lote de verificación está vacío.',
      );
    }
    if (unique.length > 100) {
      throw const ApiException(
        ApiErrorKind.invalidData,
        'El lote de verificación supera 100 fotografías.',
      );
    }
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/photos/verify-batch',
        data: {'photoIds': unique},
      );
      final items = (response.data?['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                RemotePhotoIntegrity.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.photoId.isNotEmpty)
          .toList(growable: false);
      return RemoteBatchResult(items, _evidence(response));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deletePhoto(String inspectionId, String photoId) async {
    try {
      await client.dio.delete<void>(
        '/inspections/$inspectionId/photos/$photoId',
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteInspection> submit(String id) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/submit',
        data: const {'enforceCurrentChecklist': true},
        options: Options(headers: {'Idempotency-Key': 'submit-$id'}),
      );
      return _inspection(
        response.data ?? const {},
        fallbackId: id,
        evidence: _evidence(response),
      );
    } on DioException catch (error) {
      if (_retryableDio(error)) {
        try {
          return await get(id);
        } on Object {
          // Preserve original retryable failure.
        }
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<Response<List<int>>> photoContent(
    String inspectionId,
    String photoId, {
    String size = 'thumb',
  }) => client.dio.get<List<int>>(
    '/inspections/$inspectionId/photos/$photoId/content',
    queryParameters: {'size': size},
    options: Options(responseType: ResponseType.bytes),
  );

  RemoteInspection _inspection(
    Map<String, dynamic> data, {
    String? fallbackId,
    RemoteCallEvidence? evidence,
  }) {
    final id = (data['inspection_id'] ?? data['inspectionId'] ?? fallbackId)
        ?.toString();
    if (id == null || id.isEmpty)
      throw const ApiException(
        ApiErrorKind.invalidData,
        'Respuesta de inspección inválida.',
      );
    return RemoteInspection(
      id: id,
      status: '${data['status'] ?? 'draft'}',
      hydrantId: (data['hydrant_id'] ?? data['hydrantId'])?.toString(),
      result: data['result']?.toString(),
      officialInspectionId: data['officialInspectionId']?.toString(),
      conflictId: data['conflictId']?.toString(),
      rvStatus: data['rvStatus']?.toString(),
      lastStatusChangedAt: DateTime.tryParse(
        data['lastStatusChangedAt']?.toString() ?? '',
      )?.toUtc(),
      evidence: evidence,
    );
  }

  RemoteCallEvidence _evidence(Response<dynamic> response) {
    final data = response.data;
    final body = data is Map ? data : const <String, dynamic>{};
    return RemoteCallEvidence(
      statusCode: response.statusCode ?? 0,
      method: response.requestOptions.method,
      logicalEndpoint: response.requestOptions.path,
      requestId:
          body['requestId']?.toString() ??
          response.headers.value('x-request-id') ??
          response.requestOptions.headers['X-Request-ID']?.toString(),
    );
  }

  bool _retryableDio(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      const {502, 503, 504}.contains(error.response?.statusCode);
}

// ignore_for_file: curly_braces_in_flow_control_structures
