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
  test('actualizaciones permanecen desactivadas en builds normales', () {
    expect(AppConfig.appUpdatesEnabled, isFalse);
  });
  test('AppConfig lee entorno y URL explícitos', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'development',
      apiBaseUrlOverride: 'https://example.invalid/api/v1',
    );
    expect(config.isDevelopment, isTrue);
    expect(config.apiBaseUrl.path, '/api/v1');
  });

  test('AppConfig usa el endpoint aprobado si producción no inyecta URL', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'production',
      apiBaseUrlOverride: '',
      debugMode: false,
    );
    expect(config.apiBaseUrl.toString(), AppConfig.productionBaseUrl);
  });

  test('AppConfig rechaza URL ausente fuera de producción', () {
    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: '',
      ),
      throwsStateError,
    );
  });

  test('AppConfig rechaza URL inválida', () {
    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'test',
        apiBaseUrlOverride: 'no-es-url',
      ),
      throwsStateError,
    );
  });

  test('AppConfig rechaza ambiente desconocido', () {
    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'local',
        apiBaseUrlOverride: 'https://example.invalid/api/v1',
      ),
      throwsStateError,
    );
  });

  test('AppConfig rechaza HTTP fuera de la excepción autorizada', () {
    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'http://example.invalid/api/v1',
      ),
      throwsStateError,
    );
  });

  test('AppConfig acepta configuración HTTPS inyectada para pruebas', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'test',
      apiBaseUrlOverride: 'https://example.invalid/api/v1',
    );
    expect(config.environment, 'test');
    expect(config.apiBaseUrl.host, 'example.invalid');
  });

  test('AppConfig permite únicamente el endpoint HTTP de producción', () {
    final config = AppConfig.fromEnvironment(
      environmentOverride: 'production',
      apiBaseUrlOverride: AppConfig.productionBaseUrl,
      debugMode: false,
    );
    expect(config.apiBaseUrl.host, 'cifra.aquafim.com');
    expect(config.apiBaseUrl.port, 3002);

    expect(
      () => AppConfig.fromEnvironment(
        environmentOverride: 'production',
        apiBaseUrlOverride: 'http://otro.example:3002/api/v1',
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
      userId: 'user',
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
        '{"sessionId":"session","userId":"user","crewId":"crew","role":"field","accessToken":"access","refreshToken":"refresh","tokenId":"token"}',
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

  test(
    'cambio A → B reemplaza tokens solo después de autenticar correctamente',
    () async {
      final storage = MemorySessionStorage()
        ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
        ..value = const FieldSession(
          sessionId: 'session-a',
          userId: 'user-a',
          accessToken: 'access-a',
          refreshToken: 'refresh-a',
          installationId: '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a',
          email: 'a@example.test',
        );
      var valid = false;
      final adapter = FakeHttpAdapter((options) async {
        expect(options.extra['skipAuth'], isTrue);
        expect(options.headers['Authorization'], isNull);
        if (!valid) {
          return jsonResponse(
            '{"type":"invalid-registration","detail":"Credenciales inválidas."}',
            422,
          );
        }
        return jsonResponse(
          '{"sessionId":"session-b","userId":"user-b","crewId":"crew-b","role":"field","accessToken":"access-b","refreshToken":"refresh-b"}',
          201,
        );
      });
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
      const registration = FieldRegistration(
        name: 'Usuario B',
        email: 'b@example.test',
        phone: '4491234567',
        crew: 'crew b',
      );

      await expectLater(
        repository.start(registration),
        throwsA(isA<ApiException>()),
      );
      expect(storage.value?.userId, 'user-a');
      expect(storage.value?.accessToken, 'access-a');

      valid = true;
      final sessionB = await repository.start(registration);
      expect(sessionB.userId, 'user-b');
      expect(storage.value?.userId, 'user-b');
      expect(storage.value?.accessToken, 'access-b');
      expect(storage.value?.refreshToken, 'refresh-b');
    },
  );

  test(
    'cierre sin conexión elimina tokens locales y conserva instalación',
    () async {
      final storage = MemorySessionStorage()
        ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
        ..value = const FieldSession(
          sessionId: 'session-a',
          userId: 'user-a',
          accessToken: 'access-a',
          refreshToken: 'refresh-a',
          installationId: '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a',
        );
      final adapter = FakeHttpAdapter(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
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
          version: '0.2.0',
          buildNumber: '3',
        ),
      );

      expect(await repository.end(), isFalse);
      expect(await storage.read(), isNull);
      expect(storage.pendingLogout?.refreshToken, 'refresh-a');
      expect(await storage.installationId(), storage.installation);
    },
  );

  test(
    'logout pendiente se confirma y se elimina antes del siguiente login',
    () async {
      final storage = MemorySessionStorage()
        ..pendingLogout = const FieldSession(
          sessionId: 'old-session',
          userId: 'old-user',
          accessToken: '',
          refreshToken: 'old-refresh',
          installationId: 'installation',
        );
      final adapter = FakeHttpAdapter((options) async => jsonResponse('', 204));
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = FieldSessionRepository(
        client: ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'test',
            apiBaseUrlOverride: 'https://example.test/api/v1',
          ),
          sessionStorage: storage,
          dio: dio,
        ),
        storage: storage,
        packageInfo: PackageInfo(
          appName: 'DIAGNOSTICO HIDRANTES',
          packageName: 'ddr001diag',
          version: '0.2.0',
          buildNumber: '3',
        ),
      );
      expect(await repository.completePendingLogout(), isTrue);
      expect(storage.pendingLogout, isNull);
      expect(adapter.requests.single.path, '/field-sessions/old-session/end');
    },
  );

  test('restauración conserva sesión local cuando no hay conexión', () async {
    final storage = MemorySessionStorage()
      ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
      ..value = const FieldSession(
        sessionId: 'session',
        userId: 'user',
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

  test(
    'restauración conserva sesión ante 401 sin código de revocación',
    () async {
      final storage = MemorySessionStorage()
        ..value = const FieldSession(
          sessionId: 'session',
          userId: 'user',
          accessToken: 'expired-access',
          refreshToken: 'expired-refresh',
          installationId: 'installation',
        );
      final adapter = FakeHttpAdapter(
        (options) async => jsonResponse('{"title":"Unauthorized"}', 401),
      );
      final repository = FieldSessionRepository(
        client: ApiClient(
          config: AppConfig.fromEnvironment(
            environmentOverride: 'test',
            apiBaseUrlOverride: 'https://example.test/api/v1',
          ),
          sessionStorage: storage,
          dio: Dio()..httpClientAdapter = adapter,
        ),
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
      expect(storage.value?.refreshToken, 'expired-refresh');
      expect(storage.clearCalls, 0);
    },
  );

  test('refresh rotativo es único para solicitudes simultáneas', () async {
    final storage = MemorySessionStorage()
      ..installation = '9d025d12-bc54-4aa2-8237-e2fb1fa0d67a'
      ..value = const FieldSession(
        sessionId: 'session',
        userId: 'user',
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

  test('fallo de red durante refresh conserva la sesión persistida', () async {
    final storage = MemorySessionStorage()
      ..value = const FieldSession(
        sessionId: 'session',
        userId: 'user',
        accessToken: 'expired-access',
        refreshToken: 'valid-refresh',
        installationId: 'installation',
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
        environmentOverride: 'test',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );

    await expectLater(client.refreshSession(), throwsA(isA<DioException>()));
    expect(storage.value?.refreshToken, 'valid-refresh');
    expect(storage.clearCalls, 0);
  });

  test(
    '500 durante refresh conserva token anterior y cola recuperable',
    () async {
      final storage = MemorySessionStorage()
        ..value = const FieldSession(
          sessionId: 'session',
          userId: 'user',
          accessToken: 'expired-access',
          refreshToken: 'previous-refresh',
          installationId: 'installation',
        );
      final adapter = FakeHttpAdapter(
        (options) async => jsonResponse('{"title":"temporary"}', 500),
      );
      final client = ApiClient(
        config: AppConfig.fromEnvironment(
          environmentOverride: 'test',
          apiBaseUrlOverride: 'https://example.test/api/v1',
        ),
        sessionStorage: storage,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(client.refreshSession(), throwsA(isA<DioException>()));
      expect(storage.value?.refreshToken, 'previous-refresh');
      expect(storage.clearCalls, 0);
    },
  );

  test('401 genérico del refresh conserva credenciales recuperables', () async {
    final storage = MemorySessionStorage()
      ..value = const FieldSession(
        sessionId: 'session',
        userId: 'user',
        accessToken: 'expired-access',
        refreshToken: 'revoked-refresh',
        installationId: 'installation',
      );
    final adapter = FakeHttpAdapter(
      (options) async => jsonResponse(
        '{"title":"Unauthorized","detail":"Session revoked."}',
        401,
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'test',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );

    await expectLater(client.refreshSession(), throwsA(isA<DioException>()));
    expect(storage.value?.refreshToken, 'revoked-refresh');
    expect(storage.clearCalls, 0);
  });

  for (final entry in {
    'SESSION_REVOKED': 'cerrada desde otro dispositivo',
    'USER_INACTIVE': 'desactivado',
    'DEVICE_BLOCKED': 'bloqueado',
    'DEVICE_BINDING_REVOKED': 'revocado',
  }.entries) {
    test('${entry.key} cierra credenciales con mensaje diferenciado', () async {
      final storage = MemorySessionStorage()
        ..value = const FieldSession(
          sessionId: 'session',
          userId: 'user',
          accessToken: 'expired',
          refreshToken: 'refresh',
          installationId: 'installation',
        );
      final adapter = FakeHttpAdapter(
        (options) async =>
            jsonResponse('{"code":"${entry.key}","detail":"definitive"}', 401),
      );
      final client = ApiClient(
        config: AppConfig.fromEnvironment(
          environmentOverride: 'test',
          apiBaseUrlOverride: 'https://example.test/api/v1',
        ),
        sessionStorage: storage,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(client.refreshSession(), throwsA(isA<DioException>()));
      expect(storage.value, isNull);
      expect(storage.clearCalls, 1);
      final request = RequestOptions(path: '/field-sessions/refresh');
      final translated = ApiException.fromDio(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 401,
            data: {'code': entry.key},
          ),
        ),
      );
      expect(translated.kind, ApiErrorKind.sessionRevoked);
      expect(translated.message, contains(entry.value));
    });
  }

  test('reintento de refresh no se interpreta como cierre de sesión', () async {
    final storage = MemorySessionStorage()
      ..value = const FieldSession(
        sessionId: 'session',
        userId: 'user',
        accessToken: 'expired',
        refreshToken: 'refresh',
        installationId: 'installation',
      );
    final adapter = FakeHttpAdapter(
      (options) async =>
          jsonResponse('{"code":"REFRESH_TOKEN_REUSE","detail":"retry"}', 401),
    );
    final client = ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'test',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(client.refreshSession(), throwsA(isA<DioException>()));
    expect(storage.value?.refreshToken, 'refresh');
    expect(storage.clearCalls, 0);
  });

  test(
    'reemplazar sesión cancela peticiones autenticadas pero no login',
    () async {
      final storage = MemorySessionStorage()
        ..value = const FieldSession(
          sessionId: 'session-a',
          userId: 'user-a',
          accessToken: 'access-a',
          refreshToken: 'refresh-a',
          installationId: 'installation',
        );
      final started = <String>[];
      final adapter = FakeHttpAdapter((options) async {
        started.add(options.path);
        await Future<void>.delayed(const Duration(seconds: 1));
        return jsonResponse('{}', 200);
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

      final privateRequest = dio.get<void>('/hydrants');
      final loginRequest = dio.post<void>(
        '/field-sessions/start',
        options: Options(extra: {'skipAuth': true}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      client.cancelAuthenticatedRequests();

      await expectLater(
        privateRequest,
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      await expectLater(loginRequest, completes);
      expect(started, containsAll(['/hydrants', '/field-sessions/start']));
    },
  );

  test('401 genérico conserva sesión y permite seguir trabajando', () {
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
    expect(
      ApiException.fromDio(unauthorized).message,
      'No fue posible verificar la sesión con el servidor. Puedes continuar trabajando y se intentará nuevamente.',
    );
    expect(ApiException.fromDio(offline).message, 'Servidor no disponible.');
  });

  test('500 se distingue de una falla de conectividad', () {
    final request = RequestOptions(path: '/inspections/id/parcel-valves');
    final failure = DioException(
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: 500),
    );

    final translated = ApiException.fromDio(failure);
    expect(translated.kind, ApiErrorKind.serverError);
    expect(translated.message, contains('respondió con un error'));
    expect(translated.message, isNot(contains('conexión')));
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

  test('conflicto 409 no introduce bloqueo local por usuario anterior', () {
    final request = RequestOptions(path: '/field-sessions/start');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {
          'type': 'https://rvs.example/problems/open-session-conflict',
          'title': 'Open session conflict',
          'detail': 'Device already has an incompatible open session.',
          'requestId': 'request-session',
        },
      ),
    );

    final translated = ApiException.fromDio(error);
    expect(translated.statusCode, 409);
    expect(translated.requestId, 'request-session');
    expect(
      translated.message,
      'No fue posible reemplazar la sesión del dispositivo. Intenta nuevamente.',
    );
    expect(translated.message, isNot(contains('usuario anterior')));
    expect(translated.message, isNot(contains('solicita cerrar')));
    expect(translated.message, isNot(contains('incompatible open session')));
  });

  test('configuración RV bloquea F02-B y conserva RV', () {
    expect(AppConfig.isInspectionTypeEnabled('a'), isTrue);
    expect(AppConfig.isInspectionTypeEnabled('b'), isFalse);
  });
}
