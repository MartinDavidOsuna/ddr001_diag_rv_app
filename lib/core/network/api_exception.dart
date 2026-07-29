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
    this.problemType,
    this.problemTitle,
    this.field,
    this.errors = const [],
  });
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? requestId, problemType, problemTitle, field;
  final List<Map<String, dynamic>> errors;

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final problem = data is Map ? data : const <String, dynamic>{};
    final requestId =
        problem['requestId']?.toString() ??
        error.response?.headers.value('x-request-id');
    final problemErrors = (problem['errors'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    final firstError = problemErrors.firstOrNull;
    final field = firstError?['path'] is List
        ? (firstError!['path'] as List).join('.')
        : null;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiException(
        ApiErrorKind.timeout,
        'El servidor tardó demasiado en responder.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ApiException(
        ApiErrorKind.serverUnavailable,
        'Servidor no disponible.',
      );
    }
    if (status == 401 || status == 403) {
      return ApiException(
        ApiErrorKind.sessionExpired,
        status == 401 ? 'Tu sesión expiró.' : 'No tienes permiso.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (status == 409) {
      final type = problem['type']?.toString() ?? '';
      final title = problem['title']?.toString().toLowerCase() ?? '';
      final detail = problem['detail']?.toString() ?? '';
      if (type.endsWith('/phone-conflict') || title == 'phone conflict') {
        return ApiException(
          ApiErrorKind.invalidData,
          'El teléfono ya está registrado con otro correo. Usa el correo asociado o un teléfono diferente.',
          statusCode: status,
          requestId: requestId,
        );
      }
      if (type.endsWith('/open-session-conflict') ||
          title == 'open session conflict' ||
          detail.toLowerCase().contains('incompatible open session')) {
        return ApiException(
          ApiErrorKind.invalidData,
          'No fue posible reemplazar la sesión del dispositivo. Intenta nuevamente.',
          statusCode: status,
          requestId: requestId,
        );
      }
      return ApiException(
        ApiErrorKind.invalidData,
        detail.isEmpty ? 'Existe un conflicto con los datos enviados.' : detail,
        statusCode: status,
        requestId: requestId,
      );
    }
    if (status == 422 || status == 400) {
      final detail = problem['detail']?.toString().trim();
      final issue = firstError?['message']?.toString().trim();
      final useful = [
        if (detail != null && detail.isNotEmpty) detail,
        if (issue != null && issue.isNotEmpty) issue,
      ].join(' · ');
      return ApiException(
        status == 422 ? ApiErrorKind.validation : ApiErrorKind.invalidData,
        useful.isEmpty
            ? (status == 422 ? 'Error de validación.' : 'Datos inválidos.')
            : useful,
        statusCode: status,
        requestId: requestId,
        problemType: problem['type']?.toString(),
        problemTitle: problem['title']?.toString(),
        field: field,
        errors: problemErrors,
      );
    }
    if (status == 408) {
      return ApiException(
        ApiErrorKind.timeout,
        'Tiempo de espera agotado.',
        statusCode: status,
        requestId: requestId,
      );
    }
    if (status == 429 || (status != null && status >= 500)) {
      return ApiException(
        ApiErrorKind.serverUnavailable,
        status == 429 ? 'Demasiadas solicitudes.' : 'Servidor no disponible.',
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
