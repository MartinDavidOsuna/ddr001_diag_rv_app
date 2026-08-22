import 'package:dio/dio.dart';

enum ApiErrorKind {
  offline,
  timeout,
  sessionExpired,
  authenticationRequired,
  sessionRevoked,
  sessionAlreadyActive,
  invalidData,
  unsupportedMedia,
  serverUnavailable,
  rateLimited,
  serverError,
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
    this.originalRuntimeType,
    this.originalMessage,
    this.retryAfter,
    this.httpMethod,
    this.logicalEndpoint,
    this.dioExceptionType,
  });
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? requestId, problemType, problemTitle, domainCode, field;
  final String? takeoverToken;
  final String? originalRuntimeType, originalMessage;
  final Duration? retryAfter;
  final String? httpMethod, logicalEndpoint, dioExceptionType;
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
      return ApiException(
        ApiErrorKind.serverUnavailable,
        'No fue posible conectar con el servidor. Revisa la red e intenta nuevamente.',
        httpMethod: error.requestOptions.method,
        logicalEndpoint: error.requestOptions.path,
        dioExceptionType: error.type.name,
        originalRuntimeType:
            error.error?.runtimeType.toString() ?? error.runtimeType.toString(),
        originalMessage: error.error?.toString() ?? error.message,
      );
    }
    if (status == 401 || status == 403) {
      const definitiveMessages = <String, String>{
        'SESSION_REVOKED':
            'Tu sesión fue cerrada desde otro dispositivo. La información guardada en este equipo se conservará.',
        'USER_INACTIVE': 'Tu usuario fue desactivado.',
        'DEVICE_BLOCKED': 'Este dispositivo fue bloqueado.',
        'DEVICE_BINDING_REVOKED': 'El acceso de este dispositivo fue revocado.',
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
        ApiErrorKind.serverUnavailable,
        'No fue posible verificar la sesión con el servidor. Puedes continuar trabajando y se intentará nuevamente.',
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
    if (status == 404) {
      const messages = <String, String>{
        'HYDRANT_NOT_FOUND':
            'El hidrante no está disponible en el catálogo del servidor.',
        'INSPECTION_NOT_FOUND':
            'La revisión remota no está disponible para continuar.',
        'PHOTO_NOT_FOUND':
            'La fotografía remota ya no está disponible y debe reconciliarse.',
      };
      return ApiException(
        ApiErrorKind.invalidData,
        messages[domainCode] ??
            'El recurso solicitado no está disponible en el servidor.',
        statusCode: status,
        requestId: requestId,
        problemType: problem['type']?.toString(),
        problemTitle: problem['title']?.toString(),
        domainCode: domainCode,
        httpMethod: error.requestOptions.method,
        logicalEndpoint: error.requestOptions.path,
        dioExceptionType: error.type.name,
        originalRuntimeType: error.runtimeType.toString(),
        originalMessage: problem['detail']?.toString() ?? error.message,
      );
    }
    if (status == 422 || status == 400) {
      final validationMessage = _validationMessage(problem, problemErrors);
      return ApiException(
        status == 422 ? ApiErrorKind.validation : ApiErrorKind.invalidData,
        status == 422
            ? validationMessage
            : 'Los datos enviados no son válidos.',
        statusCode: status,
        requestId: requestId,
        problemType: problem['type']?.toString(),
        problemTitle: problem['title']?.toString(),
        field: field,
        errors: problemErrors,
      );
    }
    if (status == 415) {
      return ApiException(
        ApiErrorKind.unsupportedMedia,
        'El formato de la fotografía no es compatible. Vuelve a capturarla e intenta nuevamente.',
        statusCode: status,
        requestId: requestId,
        problemType: problem['type']?.toString(),
        problemTitle: problem['title']?.toString(),
        domainCode: domainCode,
        httpMethod: error.requestOptions.method,
        logicalEndpoint: error.requestOptions.path,
        dioExceptionType: error.type.name,
        originalRuntimeType: error.runtimeType.toString(),
        originalMessage: problem['detail']?.toString() ?? error.message,
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
    if (status == 429) {
      final retryAfter = _retryAfter(
        error.response?.headers.value('retry-after'),
      );
      return ApiException(
        ApiErrorKind.rateLimited,
        'Demasiadas solicitudes.',
        statusCode: status,
        requestId: requestId,
        retryAfter: retryAfter,
        httpMethod: error.requestOptions.method,
        logicalEndpoint: error.requestOptions.path,
        dioExceptionType: error.type.name,
      );
    }
    if (status != null && status >= 500) {
      return ApiException(
        ApiErrorKind.serverError,
        'El servidor respondió con un error. Intenta nuevamente.',
        statusCode: status,
        requestId: requestId,
      );
    }
    return ApiException(
      ApiErrorKind.unknown,
      'No fue posible completar la sincronización. Tus datos permanecen '
      'guardados. Código: RV-HTTP-${status ?? 'DIO'}.',
      statusCode: status,
      requestId: requestId,
      domainCode: domainCode,
      httpMethod: error.requestOptions.method,
      logicalEndpoint: error.requestOptions.path,
      dioExceptionType: error.type.name,
      originalRuntimeType: error.runtimeType.toString(),
      originalMessage: error.message,
    );
  }

  @override
  String toString() => message;
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds != null) return Duration(seconds: seconds.clamp(1, 86400));
  final date = DateTime.tryParse(value)?.toUtc();
  if (date == null) return null;
  final delay = date.difference(DateTime.now().toUtc());
  return delay.isNegative ? Duration.zero : delay;
}

String _validationMessage(
  Map<dynamic, dynamic> problem,
  List<Map<String, dynamic>> errors,
) {
  final title = problem['title']?.toString().toLowerCase() ?? '';
  final detail = problem['detail']?.toString() ?? '';
  if (title == 'invalid parcel valve catalogs') {
    final valve = RegExp(
      r'valve\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(detail)?.group(1);
    return valve == null
        ? 'Una marca o diámetro de las válvulas no coincide con su catálogo. Vuelve a seleccionar ese dato.'
        : 'Una marca o diámetro de la válvula $valve no coincide con su catálogo. Vuelve a seleccionar ese dato.';
  }

  final issue = errors.firstOrNull;
  if (issue == null) {
    return 'Uno o más datos no son válidos. Revisa la información capturada.';
  }
  final path = issue['path'] is List
      ? (issue['path'] as List).map((part) => part.toString()).toList()
      : const <String>[];
  final field = _spanishField(path, issue);
  return field == null
      ? 'Uno o más datos no son válidos. Revisa la información capturada.'
      : 'El servidor rechazó $field. Revísalo e intenta nuevamente.';
}

String? _spanishField(List<String> path, Map<String, dynamic> issue) {
  final focusKey = issue['focusKey']?.toString();
  final itemCode = issue['itemCode']?.toString();
  final raw = path.isNotEmpty ? path.last : focusKey ?? itemCode;
  if (raw == null || raw.isEmpty) return null;

  final valvePosition = path.indexOf('valves');
  final valveIndex = valvePosition >= 0 && valvePosition + 1 < path.length
      ? int.tryParse(path[valvePosition + 1])
      : null;
  final valveSuffix = valveIndex == null
      ? ''
      : ' de la válvula ${valveIndex + 1}';
  const labels = <String, String>{
    'customConfigurationText': 'la configuración de válvulas',
    'configurationType': 'el tipo de configuración de válvulas',
    'valveCount': 'la cantidad de válvulas',
    'diameterId': 'el diámetro',
    'valveBrandId': 'la marca de la válvula',
    'valveBrandIllegibleReason': 'el motivo de marca ilegible',
    'pilotConnected': 'la conexión del piloto',
    'pilotBrandId': 'la marca del piloto',
    'pilotBrandIllegibleReason': 'el motivo de piloto ilegible',
    'solenoidBrandId': 'la marca del solenoide',
    'pressureGaugeBrandId': 'la marca del manómetro',
    'valves': 'las válvulas',
    'generalPhotos': 'las fotografías generales',
    'answers': 'las respuestas obligatorias',
    'slotCode': 'el tipo de fotografía',
  };
  final label = labels[raw];
  if (label != null) return '$label$valveSuffix';

  const itemLabels = <String, String>{
    'flow_meter_pulse_cable': 'la respuesta sobre el cable de pulsos',
  };
  return itemLabels[itemCode] ?? itemLabels[raw];
}
