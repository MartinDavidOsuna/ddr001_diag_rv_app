import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../domain/media/inspection_photo.dart';
import '../domain/rv_draft.dart';
import '../domain/parcel_valve_configuration.dart';

class RemoteInspection {
  const RemoteInspection({required this.id, required this.status});
  final String id, status;
}

class RemotePhoto {
  const RemotePhoto({
    required this.id,
    required this.slotCode,
    required this.status,
    this.sha256,
  });
  final String id, slotCode, status;
  final String? sha256;
}

class InspectionRemoteRepository {
  InspectionRemoteRepository(this.client);
  final ApiClient client;

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
      return _inspection(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<RemoteInspection> get(String id) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/inspections/$id',
      );
      return _inspection(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> saveAnswers(
    String id,
    List<Map<String, dynamic>> answers,
    String key,
  ) async {
    if (answers.isEmpty) return;
    try {
      await client.dio.put<Map<String, dynamic>>(
        '/inspections/$id/answers',
        data: {'answers': answers},
        options: Options(headers: {'Idempotency-Key': key}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> saveParcelValves(
    String id,
    ParcelValveConfiguration configuration,
  ) async {
    String remoteId(Map<String, dynamic>? value, String field) {
      final id = value?['catalogId']?.toString();
      if (id == null || id.isEmpty) {
        throw ApiException(
          ApiErrorKind.validation,
          '$field está pendiente de sincronización.',
        );
      }
      return id;
    }

    try {
      await client.dio.put<Map<String, dynamic>>(
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
                'valveBrandId': remoteId(
                  valve.valveBrand,
                  'La marca de válvula',
                ),
                'valveBrandDisplayValue': valve.valveBrand!['displayValue'],
                'hasSolenoid': valve.hasSolenoid,
                'solenoidBrandId': valve.hasSolenoid
                    ? remoteId(valve.solenoidBrand, 'La marca del solenoide')
                    : null,
                'solenoidBrandDisplayValue': valve.hasSolenoid
                    ? valve.solenoidBrand!['displayValue']
                    : null,
                'hasPilot': valve.hasPilot,
                'pilotBrandId': valve.hasPilot
                    ? remoteId(valve.pilotBrand, 'La marca del piloto')
                    : null,
                'pilotBrandDisplayValue': valve.hasPilot
                    ? valve.pilotBrand!['displayValue']
                    : null,
                'hasPressureGauge': valve.hasPressureGauge,
                'pressureGaugeBrandId': valve.hasPressureGauge
                    ? remoteId(
                        valve.pressureGaugeBrand,
                        'La marca del manómetro',
                      )
                    : null,
                'pressureGaugeBrandDisplayValue': valve.hasPressureGauge
                    ? valve.pressureGaugeBrand!['displayValue']
                    : null,
              },
          ],
        },
        options: Options(headers: {'Idempotency-Key': 'parcel-valves-$id'}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> saveLocation(
    String id,
    RvLocationSample sample,
    String key,
  ) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/location-samples',
        data: sample.toJson(),
        options: Options(headers: {'Idempotency-Key': key}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> saveSignal(String id, RvSignalSample sample, String key) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/signal-samples',
        data: sample.toJson(),
        options: Options(headers: {'Idempotency-Key': key}),
      );
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
      final response = await client.dio.post<Map<String, dynamic>>(
        '/inspections/$id/photos',
        data: FormData.fromMap({
          'photo': await MultipartFile.fromFile(
            photo.localPath,
            filename: photo.normalizedFilename,
          ),
          'photoId': photo.id,
          'slotCode': slotCode,
          'clientSha256': photo.sha256,
          'capturedAt': photo.capturedAt.toUtc().toIso8601String(),
          'metadata':
              '{"questionId":${photo.evidenceRequirementId == null ? 'null' : '"${photo.evidenceRequirementId}"'}}',
        }),
      );
      final data = response.data ?? const {};
      return RemotePhoto(
        id: '${data['photoId'] ?? photo.id}',
        slotCode: '${data['slotCode'] ?? slotCode}',
        status: '${data['status'] ?? 'verified'}',
        sha256: (data['normalizedSha256'] ?? data['sha256'])?.toString(),
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
            );
          })
          .toList();
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
        options: Options(headers: {'Idempotency-Key': 'submit-$id'}),
      );
      return _inspection(response.data ?? const {}, fallbackId: id);
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

  Future<void> cancel(String id, String reason) async {
    try {
      await client.dio.post<void>(
        '/inspections/$id/cancel',
        data: {'reason': reason.trim()},
        options: Options(headers: {'Idempotency-Key': 'cancel-$id'}),
      );
    } on DioException catch (error) {
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
  }) {
    final id = (data['inspection_id'] ?? data['inspectionId'] ?? fallbackId)
        ?.toString();
    if (id == null || id.isEmpty)
      throw const ApiException(
        ApiErrorKind.invalidData,
        'Respuesta de inspección inválida.',
      );
    return RemoteInspection(id: id, status: '${data['status'] ?? 'draft'}');
  }

  bool _retryableDio(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      const {502, 503, 504}.contains(error.response?.statusCode);
}

// ignore_for_file: curly_braces_in_flow_control_structures
