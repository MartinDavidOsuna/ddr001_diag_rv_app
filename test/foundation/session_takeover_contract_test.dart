import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/features/auth/data/field_session_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/foundation_fakes.dart';

void main() {
  test('SESSION_ALREADY_ACTIVE conserva código y challenge estructurados', () {
    final request = RequestOptions(path: '/field-sessions/start');
    final error = DioException(
      requestOptions: request,
      response: Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 409,
        data: const {
          'code': 'SESSION_ALREADY_ACTIVE',
          'takeoverToken': 'challenge-opaco',
          'detail': 'English backend detail must not reach UI',
        },
      ),
      type: DioExceptionType.badResponse,
    );

    final parsed = ApiException.fromDio(error);
    expect(parsed.kind, ApiErrorKind.sessionAlreadyActive);
    expect(parsed.domainCode, 'SESSION_ALREADY_ACTIVE');
    expect(parsed.takeoverToken, 'challenge-opaco');
    expect(parsed.message, 'Tu usuario ya está activo en otro dispositivo.');
  });

  test(
    'revoke usa endpoint explícito sin borrar almacenamiento local',
    () async {
      final storage = MemorySessionStorage();
      final adapter = FakeHttpAdapter(
        (options) async => ResponseBody.fromString('', 204),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = FieldSessionRepository(
        client: ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'development',
            apiBaseUrlOverride: 'https://example.test/api/v1',
          ),
          sessionStorage: storage,
          dio: dio,
        ),
        storage: storage,
        packageInfo: PackageInfo(
          appName: 'DIAGNOSTICO HIDRANTES',
          packageName: 'ddr001diag',
          version: '0.2.26',
          buildNumber: '39',
        ),
      );

      await repository.revokeExisting('challenge-opaco');

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path, '/field-sessions/revoke-existing');
      expect(adapter.requests.single.extra['skipAuth'], isTrue);
      expect(storage.clearCalls, 0);
    },
  );

  test('errores 422 del backend no exponen detalle inglés', () {
    final request = RequestOptions(path: '/field-sessions/start');
    final parsed = ApiException.fromDio(
      DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 422,
          data: const {
            'detail': 'One or more fields are invalid.',
            'errors': [
              {'message': 'Expected string'},
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    expect(parsed.message, contains('datos no son válidos'));
    expect(parsed.message, isNot(contains('Expected')));
    expect(parsed.message, isNot(contains('One or more')));
  });
}
