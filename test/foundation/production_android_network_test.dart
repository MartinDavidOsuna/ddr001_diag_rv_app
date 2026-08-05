import 'dart:io';

import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuración de producción conserva endpoint HTTP autorizado', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'production',
      apiBaseUrlOverride: AppConfig.productionBaseUrl,
    );
    expect(
      config.apiBaseUrl.toString(),
      'http://cifra.aquafim.com:3002/api/v1',
    );
  });

  test('manifest permite Internet y aplica Network Security Config', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:networkSecurityConfig'));
  });

  test(
    'cleartext se limita a cifra.aquafim.com y no se habilita globalmente',
    () {
      final xml = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      expect(xml, contains('cleartextTrafficPermitted="false"'));
      expect(xml, contains('cleartextTrafficPermitted="true"'));
      expect(xml, contains('>cifra.aquafim.com</domain>'));
      expect(xml, isNot(contains('includeSubdomains="true"')));
    },
  );

  group('causas mostradas como Servidor no disponible', () {
    test('error DNS/socket se clasifica como servidor no disponible', () {
      final translated = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/field-sessions/start'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Failed host lookup'),
        ),
      );
      expect(translated.kind, ApiErrorKind.serverUnavailable);
      expect(translated.message, 'Servidor no disponible.');
    });

    test('HTTP 500 se clasifica como servidor no disponible', () {
      final request = RequestOptions(path: '/field-sessions/start');
      final translated = ApiException.fromDio(
        DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 500),
        ),
      );
      expect(translated.kind, ApiErrorKind.serverUnavailable);
      expect(translated.statusCode, 500);
      expect(translated.message, 'Servidor no disponible.');
    });

    test('timeouts no se confunden con servidor no disponible', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final translated = ApiException.fromDio(
          DioException(
            requestOptions: RequestOptions(path: '/field-sessions/start'),
            type: type,
          ),
        );
        expect(translated.kind, ApiErrorKind.timeout);
        expect(translated.message, contains('tardó demasiado'));
      }
    });

    test('422 de login se conserva como validación, no disponibilidad', () {
      final request = RequestOptions(path: '/field-sessions/start');
      final translated = ApiException.fromDio(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 422,
            data: {
              'title': 'Validation error',
              'detail': 'One or more fields are invalid.',
              'requestId': 'diagnostic-request',
              'errors': <Object?>[],
            },
          ),
        ),
      );
      expect(translated.kind, ApiErrorKind.validation);
      expect(translated.statusCode, 422);
      expect(translated.message, isNot('Servidor no disponible.'));
    });
  });
}
