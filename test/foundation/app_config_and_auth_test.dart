import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/features/auth/data/field_session_models.dart';
import 'package:ddr001diag/features/auth/data/field_session_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/foundation_fakes.dart';

void main() {
  test('AppConfig lee entorno y URL explícitos', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'development',
      apiBaseUrlOverride: 'http://192.168.1.111:3000/api/v1',
    );
    expect(config.isDevelopment, isTrue);
    expect(config.apiBaseUrl.path, '/api/v1');
  });

  test('AppConfig rechaza URL vacía en release', () {
    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'production',
        apiBaseUrlOverride: '',
        debugMode: false,
      ),
      throwsStateError,
    );
  });

  group('validación de registro de campo', () {
    test('normaliza nombre, correo y cuadrilla', () {
      const value = FieldRegistration(
        name: '  Ana   Pérez  ',
        email: ' ANA@EJEMPLO.COM ',
        phone: '4491234567',
        crew: '  cuadrilla   norte  ',
      );
      expect(value.normalizedName, 'Ana Pérez');
      expect(value.normalizedEmail, 'ana@ejemplo.com');
      expect(value.normalizedCrew, 'CUADRILLA NORTE');
      expect(value.validate(), isNull);
    });

    test('rechaza correo inválido', () {
      const value = FieldRegistration(
        name: 'Ana Pérez',
        email: 'ana',
        phone: '4491234567',
        crew: 'A',
      );
      expect(value.validate(), contains('correo'));
    });

    test('exige teléfono de diez dígitos', () {
      const value = FieldRegistration(
        name: 'Ana Pérez',
        email: 'ana@ejemplo.com',
        phone: '123',
        crew: 'A',
      );
      expect(value.validate(), contains('10 dígitos'));
    });
  });

  test('installationId se crea una vez y la sesión se restaura', () async {
    final storage = MemorySessionStorage();
    final first = await storage.installationId();
    final second = await storage.installationId();
    expect(second, first);
    final session = FieldSession(
      sessionId: 'session',
      accessToken: 'access',
      refreshToken: 'refresh',
      installationId: first,
    );
    await storage.save(session);
    expect((await storage.read())?.refreshToken, 'refresh');
  });

  test('inicio de campo envía el contrato real y guarda tokens', () async {
    final storage = MemorySessionStorage()
      ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a';
    late FakeHttpAdapter adapter;
    adapter = FakeHttpAdapter((options) async {
      final body = Map<String, dynamic>.from(options.data as Map);
      expect(
        body.keys,
        containsAll(['name', 'email', 'phone', 'crew', 'device']),
      );
      expect(
        (body['device'] as Map).keys,
        containsAll([
          'installationId',
          'platform',
          'manufacturer',
          'model',
          'androidVersion',
          'appVersion',
        ]),
      );
      return jsonResponse(
        '{"sessionId":"session","accessToken":"access","refreshToken":"refresh","tokenId":"token"}',
        201,
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );
    final repository = FieldSessionRepository(
      client: client,
      storage: storage,
      packageInfo: PackageInfo(
        appName: 'DIAGNOSTICO HIDRANTES',
        packageName: 'ddr001diag',
        version: '0.2.0',
        buildNumber: '3',
      ),
      deviceLoader: () async => const DeviceDescriptor(
        platform: 'android',
        manufacturer: 'Google',
        model: 'Pixel',
        androidVersion: '16',
        appVersion: '0.2.0+3',
      ),
    );
    final session = await repository.start(
      const FieldRegistration(
        name: ' Ana  Pérez ',
        email: 'ANA@EJEMPLO.COM',
        phone: '4491234567',
        crew: 'norte 1',
      ),
    );
    expect(session.sessionId, 'session');
    expect(storage.value?.accessToken, 'access');
    expect(adapter.requests.single.extra['skipAuth'], isTrue);
  });

  test('restauración conserva sesión local cuando no hay conexión', () async {
    final storage = MemorySessionStorage()
      ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
      ..value = const FieldSession(
        sessionId: 'session',
        accessToken: 'access',
        refreshToken: 'refresh',
        installationId: '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a',
      );
    final adapter = FakeHttpAdapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );
    final repository = FieldSessionRepository(
      client: client,
      storage: storage,
      packageInfo: PackageInfo(
        appName: 'DIAGNOSTICO HIDRANTES',
        packageName: 'ddr001diag',
        version: '0.2.0',
        buildNumber: '3',
      ),
    );
    expect(await repository.restore(), isNotNull);
    expect(repository.lastRestoreOffline, isTrue);
  });

  test('refresh rotativo es único para solicitudes simultáneas', () async {
    final storage = MemorySessionStorage()
      ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
      ..value = const FieldSession(
        sessionId: 'session',
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        installationId: '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a',
      );
    var refreshCalls = 0;
    final adapter = FakeHttpAdapter((options) async {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return jsonResponse(
        '{"accessToken":"new-access","refreshToken":"new-refresh"}',
        200,
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );
    final results = await Future.wait([
      client.refreshSession(),
      client.refreshSession(),
      client.refreshSession(),
    ]);
    expect(refreshCalls, 1);
    expect(results.every((e) => e?.accessToken == 'new-access'), isTrue);
    expect(storage.value?.refreshToken, 'new-refresh');
  });

  test('errores 401 y sin conexión se traducen al español', () {
    final request = RequestOptions(path: '/private');
    final unauthorized = DioException(
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: 401),
    );
    final offline = DioException(
      requestOptions: request,
      type: DioExceptionType.connectionError,
      error: 'network',
    );
    expect(ApiException.fromDio(unauthorized).message, 'Sesión expirada.');
    expect(ApiException.fromDio(offline).message, 'Sin conexión.');
  });

  test('conflicto de teléfono explica cómo corregir el inicio de sesión', () {
    final request = RequestOptions(path: '/field-sessions/start');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {
          'type': 'https://rvs.example/problems/phone-conflict',
          'title': 'Phone conflict',
          'requestId': 'request-phone',
        },
      ),
    );

    final translated = ApiException.fromDio(error);
    expect(translated.statusCode, 409);
    expect(translated.requestId, 'request-phone');
    expect(translated.message, contains('teléfono ya está registrado'));
  });

  test('conflicto de sesión abierta identifica el dispositivo', () {
    final request = RequestOptions(path: '/field-sessions/start');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {
          'type': 'https://rvs.example/problems/open-session-conflict',
          'title': 'Open session conflict',
          'requestId': 'request-session',
        },
      ),
    );

    final translated = ApiException.fromDio(error);
    expect(translated.statusCode, 409);
    expect(translated.requestId, 'request-session');
    expect(translated.message, contains('sesión abierta de otro usuario'));
  });

  test('configuración RV bloquea F02-B y conserva RV', () {
    expect(AppConfig.isInspectionTypeEnabled('a'), isTrue);
    expect(AppConfig.isInspectionTypeEnabled('b'), isFalse);
  });
}
