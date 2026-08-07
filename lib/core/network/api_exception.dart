import 'package:dio/dio.dart';

enum ApiErrorKind {
  offline,
  timeout,
  sessionExpired,
  authenticationRequired,
  sessionRevoked,
  sessionAlreadyActive,
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
    this.domainCode,
    this.field,
    this.errors = const [],
    this.takeoverToken,
  });
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? requestId, problemType, problemTitle, domainCode, field;
  final String? takeoverToken;
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
    final domainCode = problem['code']?.toString();
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
      const definitiveMessages = <String, String>{
        'SESSION_REVOKED':
            'Tu sesión fue cerrada desde otro dispositivo. La información guardada en este equipo se conservará.',
        'USER_INACTIVE': 'Tu usuario fue desactivado.',
        'DEVICE_BLOCKED': 'Este dispositivo fue bloqueado.',
        'DEVICE_BINDING_REVOKED': 'El acceso de este dispositivo fue revocado.',
        'REFRESH_TOKEN_REUSE':
            'La seguridad de la sesión requiere iniciar nuevamente.',
      };
      if (definitiveMessages.containsKey(domainCode)) {
        return ApiException(
          ApiErrorKind.sessionRevoked,
          definitiveMessages[domainCode]!,
          statusCode: status,
          requestId: requestId,
          domainCode: domainCode,
        );
      }
      return ApiException(
        ApiErrorKind.authenticationRequired,
        'Sin conexión. Puedes continuar trabajando; los cambios se sincronizarán después.',
        statusCode: status,
        requestId: requestId,
        domainCode: domainCode,
      );
    }
    if (status == 409) {
      final type = problem['type']?.toString() ?? '';
      final title = problem['title']?.toString().toLowerCase() ?? '';
      final detail = problem['detail']?.toString() ?? '';
      const conflictMessages = <String, String>{
        'PHONE_EMAIL_MISMATCH':
            'El correo y el teléfono deben pertenecer al mismo usuario.',
        'USER_ACTIVE_ON_ANOTHER_DEVICE':
            'Tu usuario ya está activo en otro dispositivo.',
        'SESSION_ALREADY_ACTIVE':
            'Tu usuario ya está activo en otro dispositivo.',
        'DEVICE_ASSIGNED_TO_ANOTHER_USER':
            'Este dispositivo está asignado a otro usuario. Debe cerrar sesión primero.',
      };
      if (conflictMessages.containsKey(domainCode)) {
        return ApiException(
          domainCode == 'SESSION_ALREADY_ACTIVE'
              ? ApiErrorKind.sessionAlreadyActive
              : ApiErrorKind.invalidData,
          conflictMessages[domainCode]!,
          statusCode: status,
          requestId: requestId,
          domainCode: domainCode,
          takeoverToken: problem['takeoverToken']?.toString(),
        );
      }
      if (type.endsWith('/phone-conflict') || title == 'phone conflict') {
        return ApiException(
          ApiErrorKind.invalidData,
          'El teléfono ya está registrado con otro correo. Usa el correo asociado o un teléfono diferente.',
          statusCode: status,
          requestId: requestId,
          domainCode: domainCode,
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
          domainCode: domainCode,
        );
      }
      return ApiException(
        ApiErrorKind.invalidData,
        'Existe un conflicto con los datos enviados.',
        statusCode: status,
        requestId: requestId,
        domainCode: domainCode,
      );
    }
    if (status == 422 || status == 400) {
      return ApiException(
        status == 422 ? ApiErrorKind.validation : ApiErrorKind.invalidData,
        status == 422
            ? 'Uno o más datos no son válidos. Revisa la información capturada.'
            : 'Los datos enviados no son válidos.',
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
      domainCode: domainCode,
    );
  }

  @override
  String toString() => message;
}
