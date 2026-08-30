import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/data/field_session_models.dart';
import '../../features/auth/data/session_secure_storage.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  static const _diagnostics = MethodChannel(
    'com.aquafim.ddr001diag/api_diagnostics',
  );
  ApiClient({
    required AppConfig config,
    required SessionStorage sessionStorage,
    Dio? dio,
  }) : _storage = sessionStorage,
       dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.apiBaseUrl.toString().replaceAll(
                 RegExp(r'/$'),
                 '',
               ),
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 30),
               headers: const {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['startedAt'] = DateTime.now().microsecondsSinceEpoch;
          handler.next(options);
        },
        onError: _retrySafeGet,
      ),
    );
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: (response, handler) {
          _releaseRequest(response.requestOptions);
          handler.next(response);
        },
        onError: _onError,
      ),
    );
    if (kDebugMode) {
      this.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('[API] ${options.method} ${options.uri}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            final elapsed = _elapsed(response.requestOptions);
            final size = _responseSize(response.data);
            debugPrint(
              '[API] ${response.requestOptions.method} '
              '${response.requestOptions.path} → ${response.statusCode} → '
              '${elapsed.inMilliseconds} ms → ~$size bytes → intento '
              '${response.requestOptions.extra['retryAttempt'] ?? 1}',
            );
            handler.next(response);
          },
          onError: (error, handler) {
            final data = error.response?.data;
            final problem = data is Map ? data : const {};
            final errors = (problem['errors'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (issue) => {
                    'path': issue['path'],
                    'code': issue['code'],
                    'expected': issue['expected'],
                    'received': issue['received'],
                    'message': issue['message'],
                  },
                )
                .toList();
            debugPrint(
              '[API] ERROR statusCode=${error.response?.statusCode ?? '-'} '
              'dioType=${error.type.name} '
              'errorType=${error.error?.runtimeType ?? '-'} '
              'method=${error.requestOptions.method} '
              'path=${error.requestOptions.path} '
              'elapsedMs=${_elapsed(error.requestOptions).inMilliseconds} '
              'attempt=${error.requestOptions.extra['retryAttempt'] ?? 1} '
              'message=${error.message ?? '-'} '
              'requestId=${problem['requestId'] ?? error.response?.headers.value('x-request-id') ?? '-'} '
              'problem.type=${problem['type'] ?? '-'} '
              'problem.title=${problem['title'] ?? '-'} '
              'problem.detail=${problem['detail'] ?? '-'} '
              'problem.errors=$errors',
            );
            handler.next(error);
          },
        ),
      );
    }
  }

  final Dio dio;
  final SessionStorage _storage;
  Future<FieldSession?>? _refreshing;
  final Set<CancelToken> _authenticatedRequests = {};

  Future<void> _retrySafeGet(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    final attempt = request.extra['retryAttempt'] as int? ?? 1;
    final maxRetries = request.extra['maxRetries'] as int? ?? 1;
    final retryable =
        request.method == 'GET' &&
        !CancelToken.isCancel(error) &&
        (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            (error.response?.statusCode ?? 0) >= 500);
    if (!retryable || attempt > maxRetries) {
      handler.next(error);
      return;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final response = await dio.fetch<dynamic>(
        request.copyWith(
          extra: {...request.extra, 'retryAttempt': attempt + 1},
        ),
      );
      handler.resolve(response);
    } on DioException catch (nextError) {
      handler.next(nextError);
    }
  }

  static Duration _elapsed(RequestOptions options) {
    final started = options.extra['startedAt'] as int?;
    if (started == null) return Duration.zero;
    return Duration(
      microseconds: DateTime.now().microsecondsSinceEpoch - started,
    );
  }

  static int _responseSize(Object? data) {
    if (data == null) return 0;
    if (data is List<int>) return data.length;
    return data.toString().length;
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.putIfAbsent('X-Request-ID', () => const Uuid().v4());
    if (options.extra['skipAuth'] != true) {
      final cancelToken = options.cancelToken ?? CancelToken();
      options.cancelToken = cancelToken;
      _authenticatedRequests.add(cancelToken);
      final session = await _storage.read();
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    _releaseRequest(request);
    final responseData = error.response?.data;
    final problem = responseData is Map ? responseData : const {};
    final issues = (problem['errors'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (issue) =>
              '${issue['code'] ?? '-'}:${issue['path'] is List ? (issue['path'] as List).join('.') : '-'}',
        )
        .take(8)
        .join(',');
    final safePath = request.path.replaceAll(
      RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}',
        caseSensitive: false,
      ),
      ':id',
    );
    final safeDiagnostic =
        'method=${request.method} path=$safePath '
        'status=${error.response?.statusCode ?? '-'} type=${error.type.name} '
        'title=${problem['title'] ?? '-'} '
        'code=${problem['code'] ?? '-'} requestId='
        '${problem['requestId'] ?? error.response?.headers.value('x-request-id') ?? '-'} '
        'issues=[$issues]';
    unawaited(
      _diagnostics.invokeMethod<void>('log', safeDiagnostic).catchError((_) {}),
    );
    if (error.response?.statusCode != 401 ||
        request.extra['skipAuth'] == true ||
        request.extra['retriedAfterRefresh'] == true ||
        request.path == '/field-sessions/refresh') {
      handler.next(error);
      return;
    }
    try {
      final session = await refreshSession();
      if (session == null) {
        handler.next(error);
        return;
      }
      final response = await dio.fetch<dynamic>(
        request.copyWith(
          headers: {
            ...request.headers,
            'Authorization': 'Bearer ${session.accessToken}',
          },
          extra: {...request.extra, 'retriedAfterRefresh': true},
        ),
      );
      handler.resolve(response);
    } on DioException catch (refreshError) {
      // A transport or server failure while rotating credentials is not a
      // revocation. Keep the persisted session so offline work and a later
      // retry can continue. Only an explicit authentication rejection is
      // definitive.
      if (_isDefinitiveRefreshRejection(refreshError)) {
        await _storage.clear();
      }
      if (kDebugMode) {
        debugPrint(
          '[AUTH] refresh finalizado result='
          '${_isDefinitiveRefreshRejection(refreshError) ? 'revoked' : 'deferred'} '
          'status=${refreshError.response?.statusCode ?? '-'} '
          'dioType=${refreshError.type.name}',
        );
      }
      handler.next(refreshError);
    } on Object {
      // An unexpected/invalid refresh response must not erase the last
      // recoverable session. It can be retried after the service recovers.
      handler.next(error);
    }
  }

  void cancelAuthenticatedRequests() {
    final active = _authenticatedRequests.toList(growable: false);
    _authenticatedRequests.clear();
    for (final token in active) {
      if (!token.isCancelled) {
        token.cancel('La sesión activa fue reemplazada.');
      }
    }
  }

  void _releaseRequest(RequestOptions request) {
    final token = request.cancelToken;
    if (token != null) _authenticatedRequests.remove(token);
  }

  Future<FieldSession?> refreshSession() {
    final active = _refreshing;
    if (active != null) return active;
    final future = _performRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<FieldSession?> _performRefresh() async {
    final current = await _storage.read();
    if (current == null) return null;
    try {
      if (kDebugMode) debugPrint('[AUTH] refresh iniciado');
      final response = await dio.post<Map<String, dynamic>>(
        '/field-sessions/refresh',
        data: {'refreshToken': current.refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = response.data ?? const {};
      final access = data['accessToken']?.toString();
      final refresh = data['refreshToken']?.toString();
      if (access == null || refresh == null) {
        throw const FormatException('tokens');
      }
      final rotated = current.copyWith(
        accessToken: access,
        refreshToken: refresh,
      );
      await _storage.save(rotated);
      if (kDebugMode) debugPrint('[AUTH] refresh finalizado result=success');
      return rotated;
    } on DioException catch (error) {
      if (_isDefinitiveRefreshRejection(error)) {
        await _storage.clear();
      }
      rethrow;
    }
  }

  static bool _isDefinitiveRefreshRejection(DioException error) =>
      const {
        'SESSION_REVOKED',
        'USER_INACTIVE',
        'DEVICE_BLOCKED',
        'DEVICE_BINDING_REVOKED',
      }.contains(
        error.response?.data is Map
            ? (error.response!.data as Map)['code']?.toString()
            : null,
      );

  Never rethrowAsApi(Object error) {
    if (error is ApiException) throw error;
    if (error is DioException) {
      throw ApiException.fromDio(error);
    }
    throw const ApiException(ApiErrorKind.unknown, 'Error desconocido.');
  }
}
