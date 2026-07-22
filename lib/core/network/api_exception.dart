import 'package:dio/dio.dart';

enum ApiErrorKind {
  offline,
  timeout,
  sessionExpired,
  invalidData,
  serverUnavailable,
  validation,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.kind,
    this.message, {
    this.statusCode,
    this.requestId,
  });
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? requestId;

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final problem = data is Map ? data : const <String, dynamic>{};
    final requestId = problem['requestId']?.toString();
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiException(
        ApiErrorKind.timeout,
        'Tiempo de espera agotado.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ApiException(ApiErrorKind.offline, 'Sin conexión.');
    }
    if (status == 401) {
      return ApiException(
        ApiErrorKind.sessionExpired,
        'Sesión expirada.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (status == 422 || status == 400) {
      return ApiException(
        status == 422 ? ApiErrorKind.validation : ApiErrorKind.invalidData,
        status == 422 ? 'Error de validación.' : 'Datos inválidos.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (status != null && status >= 500) {
      return ApiException(
        ApiErrorKind.serverUnavailable,
        'Servidor no disponible.',
        statusCode: status,
        requestId: requestId,
      );
    }
    return ApiException(
      ApiErrorKind.unknown,
      'Error desconocido.',
      statusCode: status,
      requestId: requestId,
    );
  }

  @override
  String toString() => message;
}
