import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/data/field_session_models.dart';
import '../../features/auth/data/session_secure_storage.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
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
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 25),
               sendTimeout: const Duration(seconds: 25),
               headers: const {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    if (kDebugMode) {
      this.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('[API] ${options.method} ${options.uri}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            debugPrint(
              '[API] ${response.statusCode} ${response.requestOptions.path}',
            );
            handler.next(response);
          },
          onError: (error, handler) {
            debugPrint(
              '[API] ERROR ${error.response?.statusCode ?? '-'} ${error.requestOptions.path}',
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

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.putIfAbsent('X-Request-ID', () => const Uuid().v4());
    if (options.extra['skipAuth'] != true) {
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
    } on Object {
      await _storage.clear();
      handler.next(error);
    }
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
      return rotated;
    } on Object {
      await _storage.clear();
      rethrow;
    }
  }

  Never rethrowAsApi(Object error) {
    if (error is ApiException) throw error;
    if (error is DioException) {
      throw ApiException.fromDio(error);
    }
    throw const ApiException(ApiErrorKind.unknown, 'Error desconocido.');
  }
}
